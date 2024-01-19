const std = @import("std");
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const poseidon_instance_def = @import("../../types/poseidon_instance_def.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const RunnerError = @import("../../error.zig").RunnerError;
const poseidonPermuteComp = @import("../../../math/crypto/poseidon/poseidon.zig").poseidonPermuteComp;
const MemoryError = @import("../../error.zig").MemoryError;
const CairoVMError = @import("../../error.zig").CairoVMError;
const Program = @import("../../types/program.zig").Program;
const ProgramJSON = @import("../../types/programjson.zig");
const CairoVM = @import("../../core.zig").CairoVM;
const CairoRunner = @import("../../runners/cairo_runner.zig").CairoRunner;

const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const PoseidonInstanceDef = poseidon_instance_def.PoseidonInstanceDef;

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Poseidon built-in runner
pub const PoseidonBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: usize = 0,
    /// Ratio
    ratio: ?u32,
    /// Number of cells per instance
    cells_per_instance: u32 = poseidon_instance_def.CELLS_PER_POSEIDON,
    /// Number of input cells
    n_input_cells: u32 = poseidon_instance_def.INPUT_CELLS_PER_POSEIDON,
    /// Stop pointer
    stop_ptr: ?usize = null,
    /// Included boolean flag
    included: bool,
    /// Cache
    ///
    /// Hashmap between an address in some memory segment and `Felt252` field element
    cache: AutoHashMap(Relocatable, Felt252),
    /// Number of instances per component
    instances_per_component: u32 = 1,

    /// Create a new PoseidonBuiltinRunner instance.
    ///
    /// This function initializes a new `PoseidonBuiltinRunner` instance with the provided
    /// `allocator`, `ratio`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the cache.
    /// - `ratio`: An optional 32-bit unsigned integer representing the ratio.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `PoseidonBuiltinRunner` instance.
    pub fn init(
        allocator: Allocator,
        ratio: ?u32,
        included: bool,
    ) Self {
        return .{
            .ratio = ratio,
            .included = included,
            .cache = AutoHashMap(Relocatable, Felt252).init(allocator),
        };
    }

    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        if (self.included) {
            try result.append(MaybeRelocatable.fromSegment(
                @intCast(self.base),
                0,
            ));
        }
        return result;
    }

    pub fn deinit(self: *Self) void {
        self.cache.deinit();
    }

    /// Calculate the final stack.
    ///
    /// This function calculates the final stack pointer for the Keccak runner, based on the provided `segments`, `pointer`, and `self` settings. If the runner is included,
    /// it verifies the stop pointer for consistency and sets it. Otherwise, it sets the stop pointer to zero.
    ///
    /// # Parameters
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment management.
    /// - `pointer`: A `Relocatable` pointer to the current stack pointer.
    ///
    /// # Returns
    ///
    /// A `Relocatable` pointer to the final stack pointer, or an error code if the
    /// verification fails.
    pub fn finalStack(
        self: *Self,
        segments: *MemorySegmentManager,
        pointer: Relocatable,
    ) !Relocatable {
        if (self.included) {
            const stop_pointer_addr = pointer.subUint(1) catch return RunnerError.NoStopPointer;
            const stop_pointer = try (segments.memory.get(stop_pointer_addr) orelse return RunnerError.NoStopPointer).tryIntoRelocatable();

            if (@as(
                i64,
                @intCast(self.base),
            ) != stop_pointer.segment_index) {
                return RunnerError.InvalidStopPointerIndex;
            }

            const stop_ptr = stop_pointer.offset;
            if (stop_ptr != try self.getUsedInstances(segments) * @as(
                usize,
                @intCast(self.cells_per_instance),
            )) {
                return RunnerError.InvalidStopPointer;
            }
            self.stop_ptr = stop_ptr;
            return stop_pointer_addr;
        }

        self.stop_ptr = 0;
        return pointer;
    }

    /// Get the number of used cells associated with this Keccak runner.
    ///
    /// # Parameters
    ///
    /// - `segments`: A pointer to a `MemorySegmentManager` for segment size information.
    ///
    /// # Returns
    ///
    /// The number of used cells as a `u32`, or `MemoryError.MissingSegmentUsedSizes` if
    /// the size is not available.
    pub fn getUsedCells(self: *const Self, segments: *MemorySegmentManager) !u32 {
        return segments.getSegmentUsedSize(
            @intCast(self.base),
        ) orelse MemoryError.MissingSegmentUsedSizes;
    }

    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !usize {
        return std.math.divCeil(
            usize,
            try self.getUsedCells(segments),
            @intCast(self.cells_per_instance),
        );
    }

    pub fn deduceMemoryCell(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        const index = @mod(
            @as(
                usize,
                @intCast(address.offset),
            ),
            @as(
                usize,
                @intCast(self.cells_per_instance),
            ),
        );

        if (index < self.n_input_cells) {
            return null;
        }

        if (self.cache.get(address)) |felt| return .{ .felt = felt };

        const first_input_addr = try address.subUint(index);
        const first_output_addr = try first_input_addr.addUint(self.n_input_cells);

        var input_felts = try ArrayList(Felt252).initCapacity(allocator, self.n_input_cells);
        defer input_felts.deinit();

        for (0..@as(
            usize,
            @intCast(self.n_input_cells),
        )) |i| {
            const num = (memory.get(try first_input_addr.addUint(i)) orelse return null).tryIntoFelt() catch {
                return RunnerError.BuiltinExpectedInteger;
            };

            try input_felts.append(num);
        }

        // self.n_input_cells always is size of 3, so we can use like that
        poseidonPermuteComp(input_felts.items[0..3]);
        for (0..self.n_input_cells, input_felts.items) |i, elem| {
            try self.cache.put(try first_output_addr.addUint(i), elem);
        }

        return .{ .felt = self.cache.get(address).? };
    }
};

test "PoseidonBuiltinRunner: finalStack InvalidStopPointerError" {
    var builtin = PoseidonBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    defer builtin.deinit();

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    builtin.base = 22;

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();

    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(1),
        .{ .relocatable = Relocatable.init(
            22,
            18,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.segment_used_sizes.put(22, 1999);

    try expectError(
        RunnerError.InvalidStopPointer,
        builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "PoseidonBuiltinRunner: finalStack should return TypeMismatchNotRelocatable error if data in memory at the given stop pointer address is not Relocatable" {
    var builtin = PoseidonBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    defer builtin.deinit();

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();

    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(1),
        .{ .felt = Felt252.fromInteger(10) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectError(
        CairoVMError.TypeMismatchNotRelocatable,
        builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "PoseidonBuiltinRunner: finalStack" {
    var builtin = PoseidonBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    defer builtin.deinit();

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();

    try memory_segment_manager.segment_used_sizes.put(0, 0);

    try memory_segment_manager.memory.set(
        std.testing.allocator,
        Relocatable.init(2, 1),
        .{ .relocatable = Relocatable.init(0, 0) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(memory_segment_manager, Relocatable.init(2, 2)),
    );
}

test "PoseidonBuiltinRunner: deduceMemoryCell missing input cells no error" {
    var builtin = PoseidonBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    defer builtin.deinit();

    var mem = try Memory.init(std.testing.allocator);
    defer mem.deinit();

    try mem.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{ 1, 2 } }},
    );
    defer mem.deinitData(std.testing.allocator);

    try expectEqual(
        @as(?MaybeRelocatable, null),
        try builtin.deduceMemoryCell(std.testing.allocator, Relocatable.init(0, 0), mem),
    );
}

test "PoseidonBuiltinRunner: finalStack stop ptr check" {
    var builtin = PoseidonBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    defer builtin.deinit();

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    builtin.base = 22;

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();

    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(1),
        .{ .relocatable = Relocatable.init(
            22,
            18,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.segment_used_sizes.put(22, 17);

    try expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );

    try expectEqual(
        @as(?usize, @intCast(18)),
        builtin.stop_ptr.?,
    );
}

test "PoseidonBuiltinRunner: getUsedInstances" {
    var builtin = PoseidonBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    defer builtin.deinit();

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);

    defer memory_segment_manager.deinit();

    try memory_segment_manager.segment_used_sizes.put(0, 1);

    try expectEqual(1, builtin.getUsedInstances(memory_segment_manager));
}

test "PoseidonBuiltinRunner: getUsedInstances expected error MissingSegmentUsedSizes" {
    var builtin = PoseidonBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    defer builtin.deinit();

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        builtin.getUsedInstances(memory_segment_manager),
    );
}
