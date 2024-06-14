const std = @import("std");
const pedersen_instance_def = @import("../../types/pedersen_instance_def.zig");
const Segments = @import("../../memory/segments.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const Error = @import("../../error.zig");
const CoreVM = @import("../../../vm/core.zig");
const Pedersen_instance_def = @import("../../types/pedersen_instance_def.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectError = std.testing.expectError;
const PedersenInstanceDef = Pedersen_instance_def.PedersenInstanceDef;
const CairoVM = CoreVM.CairoVM;
const MemoryError = Error.MemoryError;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const MemorySegmentManager = Segments.MemorySegmentManager;
const RunnerError = Error.RunnerError;
const pedersen_hash = @import("starknet").crypto.pedersenHash;
const CairoVMError = @import("../../../vm/error.zig").CairoVMError;

/// Hash built-in runner
pub const HashBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: usize = 0,
    /// Ratio
    ratio: ?u32,
    /// Number of cells per instance
    cells_per_instance: u32 = pedersen_instance_def.CELLS_PER_HASH,
    /// Number of input cells
    n_input_cells: u32 = pedersen_instance_def.INPUT_CELLS_PER_HASH,
    /// Stop pointer
    stop_ptr: ?usize = null,
    /// Included boolean flag
    included: bool,
    /// Number of instance per component
    instances_per_component: u32 = 1,
    /// Vector for verified addresses
    verified_addresses: ArrayList(bool),

    /// Create a new HashBuiltinRunner instance.
    ///
    /// This function initializes a new `HashBuiltinRunner` instance with the provided
    /// `allocator`, `ratio`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the `verified_addresses` list.
    /// - `ratio`: An optional 32-bit unsigned integer representing the ratio.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `HashBuiltinRunner` instance.
    pub fn init(
        allocator: Allocator,
        ratio: ?u32,
        included: bool,
    ) Self {
        return .{
            .ratio = ratio,
            .included = included,
            .verified_addresses = ArrayList(bool).init(allocator),
        };
    }

    /// Initializes memory segments and sets the base value for the Hash runner.
    ///
    /// This function adds a memory segment using the provided `segments` manager and
    /// sets the `base` value to the index of the new segment.
    ///
    /// # Parameters
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment management.
    ///
    /// # Modifies
    /// - `self`: Updates the `base` value to the new segment's index.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        // `segments.addSegment()` always returns a positive index
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    /// Initializes and returns an `ArrayList` of `MaybeRelocatable` values.
    ///
    /// If the Hash runner is included, it appends a `Relocatable` element to the `ArrayList`
    /// with the base value. Otherwise, it returns an empty `ArrayList`.
    ///
    /// # Parameters
    /// - `allocator`: An allocator for initializing the `ArrayList`.
    ///
    /// # Returns
    /// An `ArrayList` of `MaybeRelocatable` values.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();
        if (self.included) {
            try result.append(.{
                .relocatable = Relocatable.init(
                    @intCast(self.base),
                    0,
                ),
            });
        }
        return result;
    }

    /// Get the number of used cells associated with this Hash runner.
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

    /// Retrieves memory segment addresses as a tuple.
    ///
    /// Returns a tuple containing the `base` and `stop_ptr` addresses associated
    /// with the Hash runner's memory segments. The `stop_ptr` may be `null`.
    ///
    /// # Returns
    /// A tuple of `usize` and `?usize` addresses.
    pub fn getMemorySegmentAddresses(self: *Self) std.meta.Tuple(&.{ usize, ?usize }) {
        return .{ self.base, self.stop_ptr };
    }

    /// Calculates the number of used instances for the Hash runner.
    ///
    /// This function computes the number of used instances based on the available
    /// used cells and the number of cells per instance. It performs a ceiling division
    /// to ensure that any remaining cells are counted as an additional instance.
    ///
    /// # Parameters
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment information.
    ///
    /// # Returns
    /// The number of used instances as a `usize`.
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !usize {
        return std.math.divCeil(
            usize,
            try self.getUsedCells(segments),
            @intCast(self.cells_per_instance),
        );
    }

    /// Retrieves memory access `Relocatable` for the Hash runner.
    ///
    /// This function returns an `ArrayList` of `Relocatable` elements, each representing
    /// a memory access within the segment associated with the Hash runner's base.
    ///
    /// # Parameters
    /// - `allocator`: An allocator for initializing the `ArrayList`.
    /// - `vm`: A pointer to the `CairoVM` containing segment information.
    ///
    /// # Returns
    /// An `ArrayList` of `Relocatable` elements.
    pub fn getMemoryAccesses(
        self: *Self,
        allocator: Allocator,
        vm: *CairoVM,
    ) !ArrayList(Relocatable) {
        const segment_size = try (vm.segments.getSegmentUsedSize(
            @intCast(self.base),
        ) orelse MemoryError.MissingSegmentUsedSizes);
        var result = ArrayList(Relocatable).init(allocator);
        for (0..segment_size) |i| {
            try result.append(.{
                .segment_index = @intCast(self.base),
                .offset = i,
            });
        }
        return result;
    }

    /// Calculate the final stack.
    ///
    /// This function calculates the final stack pointer for the Hash runner, based on the provided `segments`, `pointer`, and `self` settings. If the runner is included,
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
        if (!self.included) {
            self.stop_ptr = 0;
            return pointer;
        }

        const stop_pointer_addr = pointer.subUint(
            @intCast(1),
        ) catch return RunnerError.NoStopPointer;
        const stop_pointer = try (segments.memory.get(stop_pointer_addr) orelse return RunnerError.NoStopPointer).intoRelocatable();
        if (@as(
            isize,
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

    pub fn deduceMemoryCell(
        self: *Self,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        // hash has already been processed
        if (address.offset % @as(u64, self.cells_per_instance) != 2) {
            return null;
        }
        if ((address.offset < self.verified_addresses.items.len) and self.verified_addresses.items[address.offset]) {
            return null;
        }

        const num_a = memory.getFelt(Relocatable.init(address.segment_index, address.offset - 1)) catch return null;

        const num_b = memory.getFelt(Relocatable.init(address.segment_index, address.offset - 2)) catch return null;

        if (self.verified_addresses.items.len <= address.offset) try self.verified_addresses.appendNTimes(false, address.offset + 1 - self.verified_addresses.items.len);

        self.verified_addresses.items[address.offset] = true;

        return MaybeRelocatable.fromFelt(pedersen_hash(num_b, num_a));
    }

    /// Frees the resources owned by this instance of `HashBuiltinRunner`.
    pub fn deinit(self: *Self) void {
        self.verified_addresses.deinit();
    }
};

test "HashBuiltinRunner: initialStack should return an empty array list if included is false" {
    const hash_instance_def = PedersenInstanceDef.init(8, 4);
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        hash_instance_def.ratio,
        false,
    );

    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer expected.deinit();
    var actual = try hash_builtin.initialStack(std.testing.allocator);
    defer actual.deinit();
    try expectEqual(
        expected,
        actual,
    );
}

test "HashBuiltinRunner: get used instances" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memory_segment_manager.segment_used_sizes.append(345);
    try expectEqual(hash_builtin.getUsedInstances(memory_segment_manager), @as(usize, @intCast(115)));
}

test "HashBuiltinRunner: final stack success" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{ 0, 0 } },
        .{ .{ 0, 1 }, .{ 0, 1 } },
        .{ .{ 2, 0 }, .{ 0, 0 } },
        .{ .{ 2, 1 }, .{ 0, 0 } },
    });

    var segment_used_size = std.ArrayList(usize).init(std.testing.allocator);

    try segment_used_size.append(0);
    vm.segments.segment_used_sizes = segment_used_size;
    const pointer = Relocatable.init(2, 2);
    try expectEqual(Relocatable.init(2, 1), try hash_builtin.finalStack(vm.segments, pointer));
}

test "HashBuiltinRunner: final stack error stop pointer" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{ 0, 0 } },
        .{ .{ 0, 1 }, .{ 0, 1 } },
        .{ .{ 2, 0 }, .{ 0, 0 } },
        .{ .{ 2, 1 }, .{ 0, 0 } },
    });

    var segment_used_size = std.ArrayList(usize).init(std.testing.allocator);
    try segment_used_size.append(999);
    vm.segments.segment_used_sizes = segment_used_size;
    const pointer = Relocatable.init(2, 2);
    try expectError(RunnerError.InvalidStopPointer, hash_builtin.finalStack(vm.segments, pointer));
}

test "HashBuiltinRunner: final stack error when not included" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        10,
        false,
    );
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{ 0, 0 } },
        .{ .{ 0, 1 }, .{ 0, 1 } },
        .{ .{ 2, 0 }, .{ 0, 0 } },
        .{ .{ 2, 1 }, .{ 0, 0 } },
    });

    try vm.segments.segment_used_sizes.append(0);

    const pointer = Relocatable.init(2, 2);
    try expectEqual(Relocatable.init(2, 2), try hash_builtin.finalStack(vm.segments, pointer));
}

test "HashBuiltinRunner: final stack error non relocatable" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        10,
        true,
    );
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{ 0, 0 } },
        .{ .{ 0, 1 }, .{ 0, 1 } },
        .{ .{ 2, 0 }, .{ 0, 0 } },
        .{ .{ 2, 1 }, .{2} },
    });

    var segment_used_size = std.ArrayList(usize).init(std.testing.allocator);
    try segment_used_size.append(0);

    vm.segments.segment_used_sizes = segment_used_size;

    const pointer = Relocatable.init(2, 2);
    try expectError(CairoVMError.TypeMismatchNotRelocatable, hash_builtin.finalStack(vm.segments, pointer));
}

test "HashBuiltinRunner: deduce memory cell pedersen for preset memory valid" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        8,
        true,
    );
    defer hash_builtin.verified_addresses.deinit();

    const memory_segment_manager = try Segments.MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    const verified_addresses = [_]bool{ false, false, false, false, false, true };
    try memory_segment_manager.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 3 }, .{32} },
        .{ .{ 0, 4 }, .{72} },
        .{ .{ 0, 5 }, .{0} },
    });
    const res = (try hash_builtin.deduceMemoryCell(Relocatable.init(0, 5), memory_segment_manager.memory)).?;
    try expectEqual(
        MaybeRelocatable.fromInt(u256, 0x73b3ec210cccbb970f80c6826fb1c40ae9f487617696234ff147451405c339f),
        res,
    );

    try expectEqualSlices(bool, &verified_addresses, hash_builtin.verified_addresses.items);
}

test "HashBuiltinRunner: deduce memory cell pedersen for preset memory incorrect offset" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        8,
        true,
    );
    defer hash_builtin.verified_addresses.deinit();

    const memory_segment_manager = try Segments.MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 4 }, .{32} },
        .{ .{ 0, 5 }, .{72} },
        .{ .{ 0, 6 }, .{0} },
    });

    const res = (try hash_builtin.deduceMemoryCell(Relocatable.init(0, 6), memory_segment_manager.memory));
    try expectEqual(@as(?MaybeRelocatable, null), res);
}

test "HashBuiltinRunner: deduce memory cell pedersen for preset memory no values to hash" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        8,
        true,
    );
    defer hash_builtin.verified_addresses.deinit();

    const memory_segment_manager = try Segments.MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 4 }, .{72} },
        .{ .{ 0, 5 }, .{0} },
    });

    const res = (try hash_builtin.deduceMemoryCell(Relocatable.init(0, 5), memory_segment_manager.memory));
    try expectEqual(@as(?MaybeRelocatable, null), res);
}

test "HashBuiltinRunner: deduce memory cell pedersen for preset memory already computed" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        8,
        true,
    );
    const memory_segment_manager = try Segments.MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 3 }, .{32} },
        .{ .{ 0, 4 }, .{72} },
        .{ .{ 0, 5 }, .{0} },
    });

    hash_builtin.verified_addresses.deinit();
    hash_builtin.verified_addresses = ArrayList(bool).init(std.testing.allocator);
    try hash_builtin.verified_addresses.insertSlice(0, &[_]bool{ false, false, false, false, false, true });
    defer hash_builtin.verified_addresses.deinit();

    const res = (try hash_builtin.deduceMemoryCell(Relocatable.init(0, 5), memory_segment_manager.memory));
    try expectEqual(@as(?MaybeRelocatable, null), res);
}

test "HashBuiltinRunner: get memory segment addresses" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        256,
        true,
    );
    const expected: std.meta.Tuple(&.{ usize, ?usize }) = .{ 0, @as(?usize, null) };
    const actual: std.meta.Tuple(&.{ usize, ?usize }) = hash_builtin.getMemorySegmentAddresses();
    try expectEqual(expected, actual);
}

test "HashBuiltinRunner: get memory accesses missing segment used sizes" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        256,
        true,
    );

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const actual = hash_builtin.getMemoryAccesses(std.testing.allocator, &vm);
    try expectError(MemoryError.MissingSegmentUsedSizes, actual);
}

test "HashBuiltinRunner: get memory accesses empty" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        256,
        true,
    );

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var segment_used_size = std.ArrayList(usize).init(std.testing.allocator);

    try segment_used_size.append(0);
    vm.segments.segment_used_sizes = segment_used_size;

    var actual = try hash_builtin.getMemoryAccesses(std.testing.allocator, &vm);
    try expectEqualSlices(Relocatable, &[_]Relocatable{}, try actual.toOwnedSlice());
}

test "HashBuiltinRunner: get memory accesses valid" {
    var hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        256,
        true,
    );

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.segment_used_sizes.append(4);

    const expected = [_]Relocatable{ Relocatable.init(@as(i64, @intCast(hash_builtin.base)), 0), Relocatable.init(@as(i64, @intCast(hash_builtin.base)), 1), Relocatable.init(@as(i64, @intCast(hash_builtin.base)), 2), Relocatable.init(@as(i64, @intCast(hash_builtin.base)), 3) };

    var actual = try hash_builtin.getMemoryAccesses(std.testing.allocator, &vm);
    defer actual.deinit();
    try expectEqualSlices(Relocatable, &expected, actual.items);
}

test "HashBuiltinRunner: get used cells missing segment used sizes" {
    const hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        256,
        true,
    );

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try expectError(MemoryError.MissingSegmentUsedSizes, hash_builtin.getUsedCells(vm.segments));
}

test "HashBuiltinRunner: get used cells empty" {
    const hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        256,
        true,
    );

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.segment_used_sizes.append(0);

    try expectEqual(@as(?usize, 0), try hash_builtin.getUsedCells(vm.segments));
}

test "HashBuiltinRunner: get used cells valid" {
    const hash_builtin = HashBuiltinRunner.init(
        std.testing.allocator,
        256,
        true,
    );

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.segment_used_sizes.append(4);

    try expectEqual(@as(?usize, 4), try hash_builtin.getUsedCells(vm.segments));
}
