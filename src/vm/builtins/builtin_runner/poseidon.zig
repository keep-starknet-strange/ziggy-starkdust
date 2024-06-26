const std = @import("std");
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const poseidon_instance_def = @import("../../types/poseidon_instance_def.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const RunnerError = @import("../../error.zig").RunnerError;
const starknet = @import("starknet");
const MemoryError = @import("../../error.zig").MemoryError;
const CairoVMError = @import("../../error.zig").CairoVMError;
const Program = @import("../../types/program.zig").Program;
const ProgramJSON = @import("../../types/programjson.zig");
const CairoVM = @import("../../core.zig").CairoVM;
const CairoRunner = @import("../../runners/cairo_runner.zig").CairoRunner;
const BuiltinRunner = @import("./builtin_runner.zig").BuiltinRunner;

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

    pub const INPUT_CELLS_PER_POSEIDON = poseidon_instance_def.INPUT_CELLS_PER_POSEIDON;

    /// Base
    base: usize = 0,
    /// Ratio
    ratio: ?u32,
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
    pub fn init(allocator: Allocator, ratio: ?u32, included: bool) Self {
        return .{
            .ratio = ratio,
            .included = included,
            .cache = AutoHashMap(Relocatable, Felt252).init(allocator),
        };
    }

    /// Initializes memory segments for the PoseidonBuiltinRunner.
    ///
    /// This function initializes memory segments for the PoseidonBuiltinRunner instance.
    /// It adds a new memory segment via the provided `segments` argument.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` to add a new segment.
    ///
    /// # Errors
    ///
    /// This function returns an error if adding a new segment fails.
    ///
    /// # Safety
    ///
    /// This function operates on memory segments and may cause undefined behavior if used incorrectly.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    /// Retrieves memory segment addresses for the PoseidonBuiltinRunner.
    ///
    /// This function returns a tuple containing the base address and stop pointer of memory segments
    /// used by the PoseidonBuiltinRunner instance.
    ///
    /// # Returns
    ///
    /// A tuple containing the base address and stop pointer of memory segments.
    pub fn getMemorySegmentAddresses(self: *const Self) std.meta.Tuple(&.{ usize, ?usize }) {
        return .{ self.base, self.stop_ptr };
    }

    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();
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

    /// Calculate the final stack pointer.
    ///
    /// This function calculates the final stack pointer for the Poseidon runner, based on the provided `segments`, `pointer`, and `self` settings. If the runner is included,
    /// it verifies the stop pointer for consistency and sets it. Otherwise, it sets the stop pointer to zero.
    ///
    /// # Parameters
    ///
    /// - `self`: A pointer to the `PoseidonBuiltinRunner` instance.
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment management.
    /// - `pointer`: A `Relocatable` pointer to the current stack pointer.
    ///
    /// # Returns
    ///
    /// A `Relocatable` pointer to the final stack pointer, or an error code if the verification fails.
    pub fn finalStack(
        self: *Self,
        segments: *MemorySegmentManager,
        pointer: Relocatable,
    ) !Relocatable {
        // Check if the runner is included. If not, set stop pointer to zero and return pointer.
        if (!self.included) {
            self.stop_ptr = 0;
            return pointer;
        }

        // Calculate the address of the stop pointer and handle potential errors.
        const stop_pointer_addr = pointer.subUint(1) catch return RunnerError.NoStopPointer;

        // Retrieve the stop pointer value from memory and convert it into a Relocatable pointer.
        const stop_pointer = segments.memory.getRelocatable(stop_pointer_addr) catch
            return RunnerError.NoStopPointer;

        // Verify if the base index of the runner matches the segment index of the stop pointer.
        if (self.base != stop_pointer.segment_index) return RunnerError.InvalidStopPointerIndex;

        // Calculate the expected stop pointer value based on the number of used instances.
        const stop_ptr = stop_pointer.offset;
        if (stop_ptr != try self.getUsedInstances(segments) * poseidon_instance_def.CELLS_PER_POSEIDON)
            return RunnerError.InvalidStopPointer;

        // Set the stop pointer and return the address of the stop pointer.
        self.stop_ptr = stop_ptr;
        return stop_pointer_addr;
    }

    /// Get the number of used cells associated with this Poseidon runner.
    ///
    /// # Parameters
    ///
    /// - `segments`: A pointer to a `MemorySegmentManager` for segment size information.
    ///
    /// # Returns
    ///
    /// The number of used cells as a `u32`, or `MemoryError.MissingSegmentUsedSizes` if
    /// the size is not available.
    pub fn getUsedCells(self: *const Self, segments: *MemorySegmentManager) !usize {
        return segments.getSegmentUsedSize(
            @intCast(self.base),
        ) orelse MemoryError.MissingSegmentUsedSizes;
    }

    /// Retrieves the number of used instances by the PoseidonBuiltinRunner.
    ///
    /// This function calculates and returns the number of used instances by the PoseidonBuiltinRunner
    /// based on the number of used cells in memory segments.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` containing memory segments.
    ///
    /// # Returns
    ///
    /// The number of used instances calculated based on the number of used cells.
    ///
    /// # Errors
    ///
    /// This function returns an error if retrieving the number of used cells fails.
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !usize {
        return std.math.divCeil(
            usize,
            try self.getUsedCells(segments),
            6,
        );
    }

    /// Deduce the memory cell.
    ///
    /// This function deduces the memory cell for the Poseidon runner based on the provided `address` and `memory` settings. It calculates the index of the memory cell, checks if it's an input cell,
    /// retrieves or computes the cell value, and caches it for future access.
    ///
    /// # Parameters
    ///
    /// - `self`: A pointer to the `PoseidonBuiltinRunner` instance.
    /// - `allocator`: An allocator for initializing data structures.
    /// - `address`: A `Relocatable` pointer to the memory cell address.
    /// - `memory`: A pointer to the `Memory` instance for accessing memory data.
    ///
    /// # Returns
    ///
    /// A `MaybeRelocatable` instance representing the deduced memory cell, or `null` if the cell could not be deduced.
    pub fn deduceMemoryCell(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        _ = allocator; // autofix
        // Calculate the index of the memory cell.
        const index: usize = @mod(
            @as(usize, @intCast(address.offset)),
            poseidon_instance_def.CELLS_PER_POSEIDON,
        );

        // Check if the index corresponds to an input cell, if so, return null.
        if (index < poseidon_instance_def.INPUT_CELLS_PER_POSEIDON) return null;

        // Check if the cell value is already cached, if so, return it.
        if (self.cache.get(address)) |felt| return .{ .felt = felt };

        // Calculate the addresses for the first input cell and first output cell.
        const first_input_addr = try address.subUint(index);
        const first_output_addr = try first_input_addr.addUint(poseidon_instance_def.INPUT_CELLS_PER_POSEIDON);

        // Initialize an array list to store input cell values.
        // Iterate over input cells, retrieve their values, and append them to the array list.
        var input_felts = memory.getFeltRange(first_input_addr, poseidon_instance_def.INPUT_CELLS_PER_POSEIDON) catch return RunnerError.BuiltinExpectedInteger;
        defer input_felts.deinit();

        // Perform Poseidon permutation computation on the input cells.
        // TODO: optimize to use pointer on state
        var PoseidonHasher = starknet.crypto.PoseidonHasher{
            .state = input_felts.items[0..3].*,
        };

        PoseidonHasher.permuteComp();

        // Iterate over input cells and cache their computed values.
        inline for (0..3) |i| {
            try self.cache.put(
                try first_output_addr.addUint(i),
                PoseidonHasher.state[i],
            );
        }

        // Return the cached value for the specified memory cell address.
        return .{ .felt = self.cache.get(address).? };
    }
};

test "PoseidonBuiltinRunner: getUsedInstances should return number of cells" {
    // Initialize PoseidonBuiltinRunner and MemorySegmentManager instances.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    defer builtin.deinit();
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    // Set number of used cells in segment 0 of memory_segment_manager to 1.
    try memory_segment_manager.segment_used_sizes.append(1);

    // Test if getUsedInstances returns expected number of used instances.
    try expectEqual(@as(usize, 1), try builtin.getUsedInstances(memory_segment_manager));
}

test "PoseidonBuiltinRunner: getUsedInstances expected error MissingSegmentUsedSizes" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to true.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance named `memory_segment_manager`.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Test if an error of type MemoryError.MissingSegmentUsedSizes is raised when calling the getUsedInstances method of `builtin` with `memory_segment_manager`.
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        builtin.getUsedInstances(memory_segment_manager),
    );
}

test "PoseidonBuiltinRunner: getUsedInstances for BuiltinRunner enum" {
    // Initialize a BuiltinRunner enum instance with PoseidonBuiltinRunner as its variant.
    var builtin: BuiltinRunner = .{ .Poseidon = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true) };
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Set the number of used cells in segment 0 of memory_segment_manager to 1.
    try memory_segment_manager.segment_used_sizes.append(1);

    // Test if getUsedInstances returns the expected number of used instances.
    try expectEqual(@as(usize, 1), try builtin.getUsedInstances(memory_segment_manager));
}

test "PoseidonBuiltinRunner: finalStack InvalidStopPointerError" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to true.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance named `memory_segment_manager`.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Set the base pointer of `builtin` to 22.
    builtin.base = 22;

    // Set up memory for `memory_segment_manager`.
    try memory_segment_manager.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 2, 1 }, .{ 22, 18 } }},
    );
    // Ensure proper deallocation of memory data when the test scope ends.
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // Set the number of used cells in segment 22 of `memory_segment_manager` to 1999.
    try memory_segment_manager.segment_used_sizes.appendNTimes(0, 22);
    try memory_segment_manager.segment_used_sizes.append(1999);

    // Test if an InvalidStopPointer error is raised when calling the finalStack method of `builtin`.
    try expectError(
        RunnerError.InvalidStopPointer,
        builtin.finalStack(memory_segment_manager, Relocatable.init(2, 2)),
    );
}

test "PoseidonBuiltinRunner: finalStack" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to true.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance named `memory_segment_manager`.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Set the number of used cells in segment 0 of `memory_segment_manager` to 0.
    try memory_segment_manager.segment_used_sizes.append(0);

    // Set up memory for `memory_segment_manager`.
    try memory_segment_manager.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 2, 1 }, .{ 0, 0 } }},
    );
    // Ensure proper deallocation of memory data when the test scope ends.
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // Test if the finalStack method of `builtin` returns the expected Relocatable instance.
    try expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(memory_segment_manager, Relocatable.init(2, 2)),
    );
}

test "PoseidonBuiltinRunner: finalStack with multiple segments" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to true.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance named `memory_segment_manager`.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Set the number of used cells in segment 0 of `memory_segment_manager` to 0.
    try memory_segment_manager.segment_used_sizes.append(0);

    // Set up memory for `memory_segment_manager`.
    try memory_segment_manager.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );
    // Ensure proper deallocation of memory data when the test scope ends.
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // Set the number of used cells in segment 0 of `memory_segment_manager` to 0.
    try memory_segment_manager.segment_used_sizes.append(0);

    // Test if the finalStack method of `builtin` returns the expected Relocatable instance.
    try expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(memory_segment_manager, Relocatable.init(2, 2)),
    );
}

test "PoseidonBuiltinRunner: finalStack when not included" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to false.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, false);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance named `memory_segment_manager`.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Set the number of used cells in segment 0 of `memory_segment_manager` to 0.
    try memory_segment_manager.segment_used_sizes.append(0);

    // Set up memory for `memory_segment_manager`.
    try memory_segment_manager.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );
    // Ensure proper deallocation of memory data when the test scope ends.
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // Set the number of used cells in segment 0 of `memory_segment_manager` to 0.
    try memory_segment_manager.segment_used_sizes.append(0);

    // Test if the finalStack method of `builtin` returns the expected Relocatable instance.
    // The method is called with `memory_segment_manager` and a Relocatable instance initialized with values (2, 2).
    try expectEqual(
        Relocatable.init(2, 2),
        try builtin.finalStack(memory_segment_manager, Relocatable.init(2, 2)),
    );

    // Test if the stop pointer of `builtin` is equal to 0 when it's not included.
    try expectEqual(@as(usize, 0), builtin.stop_ptr);
}

test "PoseidonBuiltinRunner: finalStack should return NoStopPointer error if data in memory at the given stop pointer address is not Relocatable" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to true.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance named `memory_segment_manager`.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Set the number of used cells in segment 0 of `memory_segment_manager` to 0.
    try memory_segment_manager.segment_used_sizes.append(0);

    // Set up memory for `memory_segment_manager` with specific segment sizes, including a non-Relocatable value at stop pointer address.
    try memory_segment_manager.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } }, // First segment size
            .{ .{ 0, 1 }, .{ 0, 1 } }, // Second segment size
            .{ .{ 2, 0 }, .{ 0, 0 } }, // Third segment size
            .{ .{ 2, 1 }, .{2} }, // Fourth segment size (contains non-Relocatable data)
        },
    );
    // Ensure proper deallocation of memory data when the test scope ends.
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // Set the number of used cells in segment 0 of `memory_segment_manager` to 0.
    try memory_segment_manager.segment_used_sizes.append(0);

    // Test if a NoStopPointer error is raised when calling the finalStack method of `builtin`.
    try expectError(
        RunnerError.NoStopPointer,
        builtin.finalStack(memory_segment_manager, Relocatable.init(2, 2)),
    );
}

test "PoseidonBuiltinRunner: finalStack stop ptr check" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to true.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a MemorySegmentManager instance named `memory_segment_manager`.
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer memory_segment_manager.deinit();

    // Set the base index of `builtin` to 22.
    builtin.base = 22;

    // Set up memory for `memory_segment_manager` with specific segment sizes.
    try memory_segment_manager.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 2, 1 }, .{ 22, 18 } }},
    );
    // Ensure proper deallocation of memory data when the test scope ends.
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // Set the number of used cells in segment 22 of `memory_segment_manager` to 17.
    try memory_segment_manager.segment_used_sizes.appendNTimes(0, 22);
    try memory_segment_manager.segment_used_sizes.append(17);

    // Test if the finalStack method of `builtin` returns the expected Relocatable instance.
    // The method is called with `memory_segment_manager` and a Relocatable instance initialized with values (2, 2).
    try expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );

    // Test if the stop pointer value is as expected.
    try expectEqual(@as(?usize, 18), builtin.stop_ptr.?);
}

test "PoseidonBuiltinRunner: deduceMemoryCell missing input cells no error" {
    // Initialize a PoseidonBuiltinRunner instance named `builtin` with a ratio of 10 and included set to true.
    var builtin = PoseidonBuiltinRunner.init(std.testing.allocator, 10, true);
    // Ensure proper deallocation of resources when the test scope ends.
    defer builtin.deinit();

    // Initialize a Memory instance named `mem`.
    var mem = try Memory.init(std.testing.allocator);
    // Ensure proper deallocation of resources when the test scope ends.
    defer mem.deinit();

    // Set up memory for `mem`.
    try mem.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );
    // Ensure proper deallocation of memory data when the test scope ends.
    defer mem.deinitData(std.testing.allocator);

    // Test if the deduceMemoryCell method of `builtin` returns null when called with missing input cells.
    try expectEqual(
        null,
        try builtin.deduceMemoryCell(std.testing.allocator, .{}, mem),
    );
}
