const std = @import("std");

const bitwise_instance_def = @import("../../types/bitwise_instance_def.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const Segments = @import("../../memory/segments.zig");
const Error = @import("../../error.zig");
const CoreVM = @import("../../../vm/core.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CairoVM = CoreVM.CairoVM;
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemoryError = Error.MemoryError;
const MemorySegmentManager = Segments.MemorySegmentManager;
const RunnerError = Error.RunnerError;
const Tuple = std.meta.Tuple;

pub const BitwiseError = error{
    InvalidBitwiseIndex,
    UnsupportedNumberOfBits,
    InvalidAddressForBitwise,
};

/// Bitwise built-in runner
pub const BitwiseBuiltinRunner = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells
    n_input_cells: u32,
    /// Built-in bitwise instance
    bitwise_builtin: bitwise_instance_def.BitwiseInstanceDef,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,
    /// Number of instance per component
    instances_per_component: u32,

    /// Retrieve the felt in memory that an address denotes as an integer within the configured `total_n_bit` limit,
    /// default is 251
    /// # Arguments
    /// - address: The address belonging to the Bitwise builtin's segment
    /// - memory: The cairo memory where addresses are looked up
    /// # Returns
    /// The felt as an integer.
    fn getIntWithinBits(self: Self, address: Relocatable, memory: *Memory) BitwiseError!u256 {
        // Attempt to retrieve the felt from memory
        const num = memory.getFelt(address) catch return BitwiseError.InvalidAddressForBitwise;

        // Check the number of bits in the felt
        if (num.numBits() > self.bitwise_builtin.total_n_bits) {
            return BitwiseError.UnsupportedNumberOfBits;
        }

        // If the felt fits within the expected amount of bits, return its integer representation
        return num.toInteger();
    }

    /// Create a new BitwiseBuiltinRunner instance.
    ///
    /// This function initializes a new `BitwiseBuiltinRunner` instance with the provided
    /// `instance_def` and `included` values.
    ///
    /// # Arguments
    ///
    /// - `instance_def`: A pointer to the `BitwiseInstanceDef` for this runner.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `BitwiseBuiltinRunner` instance.
    pub fn init(
        instance_def: *bitwise_instance_def.BitwiseInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .base = 0,
            .cells_per_instance = bitwise_instance_def.CELLS_PER_BITWISE,
            .n_input_cells = bitwise_instance_def.INPUT_CELLS_PER_BITWISE,
            .bitwise_builtin = instance_def.*,
            .stop_ptr = null,
            .included = included,
            .instances_per_component = 1,
        };
    }

    pub fn initDefault() Self {
        var default: bitwise_instance_def.BitwiseInstanceDef = .{};
        return Self.init(&default, true);
    }

    /// Initializes segments for the BitwiseBuiltinRunner instance using the provided MemorySegmentManager.
    ///
    /// This function sets the base address for the BitwiseBuiltinRunner instance by adding a segment through the MemorySegmentManager.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the BitwiseBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// An error if the addition of the segment fails, otherwise sets the base address successfully.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    /// Generates an initial stack for the BitwiseBuiltinRunner instance.
    ///
    /// This function initializes an ArrayList of MaybeRelocatable elements representing the initial stack.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `allocator`: The allocator to initialize the ArrayList.
    ///
    /// # Returns
    ///
    /// An ArrayList of MaybeRelocatable elements representing the initial stack.
    /// If the instance is marked as included, a single element initialized with the base address is returned.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();
        if (self.included) {
            try result.append(MaybeRelocatable.fromSegment(
                @intCast(self.base),
                0,
            ));
            return result;
        }
        return result;
    }

    /// Retrieves memory access `Relocatable` for the BitwiseBuiltinRunner.
    ///
    /// This function returns an `ArrayList` of `Relocatable` elements, each representing
    /// a memory access within the segment associated with the Keccak runner's base.
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
        errdefer result.deinit();
        for (0..segment_size) |i| {
            try result.append(.{
                .segment_index = @intCast(self.base),
                .offset = i,
            });
        }
        return result;
    }

    /// Creates Validation Rule in Memory
    ///
    /// # Parameters
    ///
    /// - `memory`: A `Memory` pointer of validation rules segment index.
    ///
    /// # Modifies
    ///
    /// - `memory`: Adds validation rule to `memory`.
    pub fn addValidationRule(self: *const Self, memory: *Memory) !void {
        _ = self;
        _ = memory;
    }

    /// Deduces the `MemoryCell` for a given address within the Bitwise runner's memory.
    ///
    /// This function takes an allocator, address, and a reference to the memory and returns
    /// a `MaybeRelocatable` value representing the `MemoryCell` associated with the given
    /// address. It first calculates the index of the cell within the Bitwise runner's memory
    /// segment, checks if the address corresponds to an input cell, and attempts to construct
    /// an x and y offset the address. These offsets are used to look up two `Felt252`s in memory,
    /// with a check if value is within the parameterized `total_n_bits` limit.
    /// If so, it is returned as a u256 integer and the two x and y values are computed in
    /// a given bitwise operation, determined by the index.
    ///
    /// # Parameters
    ///
    /// - `allocator`: An allocator for temporary memory allocations.
    /// - `address`: The target address for deducing the `MemoryCell`.
    /// - `memory`: A pointer to the `Memory` containing the memory segments.
    ///
    /// # Returns
    ///
    /// A `MaybeRelocatable` containing the deduced `MemoryCell`, or `null` if the address
    /// corresponds to an input cell, or an error code if any issues occur during the process.
    pub fn deduceMemoryCell(
        self: *const Self,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        const index = address.offset % self.cells_per_instance;

        if (index < self.n_input_cells) {
            return null;
        }

        // calculate offset
        const x_offset = address.subUint(index) catch {
            return BitwiseError.InvalidBitwiseIndex;
        };
        const y_offset = try x_offset.addUint(1);

        const x = try self.getIntWithinBits(x_offset, memory);
        const y = try self.getIntWithinBits(y_offset, memory);

        const res = switch (index) {
            2 => x & y, // and
            3 => x ^ y, // xor
            4 => x | y, // or
            else => return BitwiseError.InvalidBitwiseIndex,
        };

        return .{ .felt = Felt252.fromInteger(res) };
    }

    /// Retrieves memory segment addresses as a tuple.
    ///
    /// Returns a tuple containing the `base` and `stop_ptr` addresses associated
    /// with the Range Check runner's memory segments. The `stop_ptr` may be `null`.
    ///
    /// # Returns
    /// A tuple of `usize` and `?usize` addresses.
    pub fn getMemorySegmentAddresses(self: *Self) Tuple(&.{
        usize,
        ?usize,
    }) {
        return .{
            self.base,
            self.stop_ptr,
        };
    }

    /// Get the number of used cells associated with this Bitwise runner.
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

    /// Calculates the number of used diluted check units for Keccak hashing.
    ///
    /// This function determines the number of used diluted check units based on the
    /// provided `diluted_n_bits`. It takes into account the allocated virtual columns
    /// and embedded real cells, providing a count of used check units.
    ///
    /// # Parameters
    /// - `diluted_n_bits`: The number of bits for the diluted check.
    ///
    /// # Returns
    /// The number of used diluted check units as a `usize`.
    pub fn getUsedDilutedCheckUnits(self: Self, allocator: Allocator, diluted_spacing: u32, diluted_n_bits: u32) !usize {
        const total_n_bits = self.bitwise_builtin.total_n_bits;

        var partition = std.ArrayList(usize).init(allocator);
        defer partition.deinit();

        var i: usize = 0;

        while (i < total_n_bits) : (i += diluted_spacing * diluted_n_bits) {
            for (0..diluted_spacing) |j| {
                if (i + j < total_n_bits) {
                    try partition.append(i + j);
                }
            }
        }

        const partition_length = @as(usize, partition.items.len);
        var num_trimmed: usize = 0;

        for (partition.items) |element| {
            if ((element + diluted_spacing * (diluted_n_bits - 1) + 1) > total_n_bits) {
                num_trimmed += 1;
            }
        }
        return 4 * partition_length + num_trimmed;
    }

    /// Calculate the final stack.
    ///
    /// This function calculates the final stack pointer for the Bitwise runner, based on the provided `segments`, `pointer`, and `self` settings. If the runner is included,
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
            const stop_pointer_addr = pointer.subUint(
                @intCast(1),
            ) catch return RunnerError.NoStopPointer;
            const stop_pointer = try (segments.memory.get(stop_pointer_addr)).tryIntoRelocatable();
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

        self.stop_ptr = 0;
        return pointer;
    }

    /// Calculates the number of used instances for the Bitwise runner.
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
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "BitwiseBuiltinRunner: getUsedInstances should return the number of used instances" {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;

    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    try memory_segment_manager.segment_used_sizes.put(0, 1);
    try expectEqual(
        @as(usize, @intCast(1)),
        try builtin.getUsedInstances(memory_segment_manager),
    );
}

test "BitwiseBuiltinRunner: deduceMemoryCell and" {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;
    const mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);

    // when
    try Memory.setUpMemory(mem, std.testing.allocator, .{
        .{ .{ 0, 5 }, .{10} },
        .{ .{ 0, 6 }, .{12} },
        .{ .{ 0, 8 }, .{0} },
    });

    const address = Relocatable.init(0, 7);
    const expected = MaybeRelocatable{ .felt = Felt252.fromInteger(8) };

    // then
    const result = try builtin.deduceMemoryCell(address, mem);

    try expectEqual(
        expected,
        result.?,
    );
}

test "BitwiseBuiltinRunner: deduceMemoryCell xor" {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;
    const mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);

    // when
    try Memory.setUpMemory(mem, std.testing.allocator, .{
        .{ .{ 0, 5 }, .{10} },
        .{ .{ 0, 6 }, .{12} },
        .{ .{ 0, 8 }, .{0} },
    });

    const address = Relocatable.init(0, 8);
    const expected = MaybeRelocatable{ .felt = Felt252.fromInteger(6) };

    // then
    const result = try builtin.deduceMemoryCell(address, mem);
    try expectEqual(
        expected,
        result.?,
    );
}

test "BitwiseBuiltinRunner: deduceMemoryCell or" {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;
    const mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);

    // when
    try Memory.setUpMemory(mem, std.testing.allocator, .{
        .{ .{ 0, 5 }, .{10} },
        .{ .{ 0, 6 }, .{12} },
        .{ .{ 0, 8 }, .{0} },
    });

    const address = Relocatable.init(0, 9);
    const expected = MaybeRelocatable{ .felt = Felt252.fromInteger(14) };

    // then
    const result = try builtin.deduceMemoryCell(address, mem);
    try expectEqual(
        expected,
        result.?,
    );
}

test "BitwiseBuiltinRunner: deduceMemoryCell when address.offset is incorrect returns null" {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;
    const mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);

    // when
    try Memory.setUpMemory(mem, std.testing.allocator, .{
        .{ .{ 0, 3 }, .{10} },
        .{ .{ 0, 4 }, .{12} },
        .{ .{ 0, 5 }, .{0} },
    });

    const address = Relocatable.init(0, 5);

    // then
    try expectEqual(@as(?MaybeRelocatable, null), try builtin.deduceMemoryCell(address, mem));
}

test "BitwiseBuiltinRunner: deduceMemoryCell when address points to nothing in memory" {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    const address = Relocatable.init(0, 3);

    // then
    try expectError(BitwiseError.InvalidAddressForBitwise, builtin.deduceMemoryCell(address, mem));
}

test "BitwiseBuiltinRunner: deduceMemoryCell should return InvalidAddressForBitwise when address points to relocatable variant of MaybeRelocatable " {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);
    // when
    const address = Relocatable.init(0, 3);

    try Memory.setUpMemory(mem, std.testing.allocator, .{
        .{ .{ 0, 3 }, .{ 0, 3 } },
    });

    // then
    try expectError(BitwiseError.InvalidAddressForBitwise, builtin.deduceMemoryCell(address, mem));
}

test "BitwiseBuiltinRunner: deduceMemoryCell should return UnsupportedNumberOfBits error when address points to felt greater than BITWISE_TOTAL_N_BITS" {

    // given
    var builtin = BitwiseBuiltinRunner.initDefault();

    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);
    // when
    const address = Relocatable.init(0, 7);

    try Memory.setUpMemory(mem, std.testing.allocator, .{
        .{ .{ 0, 5 }, .{std.math.pow(u256, 2, bitwise_instance_def.TOTAL_N_BITS_BITWISE_DEFAULT) + 1} },
        .{ .{ 0, 6 }, .{12} },
        .{ .{ 0, 8 }, .{0} },
    });

    // then
    try expectError(BitwiseError.UnsupportedNumberOfBits, builtin.deduceMemoryCell(address, mem));
}

test "BitwiseBuiltinRunner: getUsedDilutedCheckUnits should pass test cases" {
    // cases gratefully taken from cairo_vm_in_{go/rust} tests
    const cases: [3]struct {
        when: struct {
            diluted_spacing: u32,
            diluted_n_bits: u32,
        },
        then: usize,
    } = .{
        .{
            .when = .{
                .diluted_spacing = 12,
                .diluted_n_bits = 2,
            },
            .then = 535,
        },
        .{
            .when = .{
                .diluted_spacing = 30,
                .diluted_n_bits = 56,
            },
            .then = 150,
        },
        .{
            .when = .{
                .diluted_spacing = 50,
                .diluted_n_bits = 25,
            },
            .then = 250,
        },
    };

    inline for (cases) |case| {

        // given
        var builtin = BitwiseBuiltinRunner.initDefault();
        const allocator = std.testing.allocator;

        // when
        const result = try builtin.getUsedDilutedCheckUnits(allocator, case.when.diluted_spacing, case.when.diluted_n_bits);

        // then
        try expectEqual(@as(usize, case.then), result);
    }
}
