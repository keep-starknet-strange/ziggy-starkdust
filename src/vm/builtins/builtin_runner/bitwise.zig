const std = @import("std");

const bitwise_instance_def = @import("../../types/bitwise_instance_def.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const Segments = @import("../../memory/segments.zig");
const Error = @import("../../error.zig");
const CoreVM = @import("../../../vm/core.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const CairoVM = CoreVM.CairoVM;
const CairoVMError = Error.CairoVMError;
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

const BITWISE_INSTANCE_DEF = bitwise_instance_def.BitwiseInstanceDef{};

/// Bitwise built-in runner
pub const BitwiseBuiltinRunner = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32 = BITWISE_INSTANCE_DEF.ratio,
    /// Base
    base: usize = 0,
    /// the number of memory cells per invocation
    cells_per_instance: u32 = bitwise_instance_def.CELLS_PER_BITWISE,
    /// The number of the first memory cells in each invocation that that form the input.
    /// The rest of the cells are considered output.
    n_input_cells: u32 = bitwise_instance_def.INPUT_CELLS_PER_BITWISE,
    /// Built-in bitwise instance
    bitwise_builtin: bitwise_instance_def.BitwiseInstanceDef = BITWISE_INSTANCE_DEF,
    /// Stop pointer
    stop_ptr: ?usize = null,
    /// Included boolean flag
    included: bool = true,
    /// The number of invocations being handled in each call to the corresponding component
    instances_per_component: u32 = 1,

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
        instance_def: *const bitwise_instance_def.BitwiseInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .bitwise_builtin = instance_def.*,
            .included = included,
        };
    }

    /// Initializes segments for the Bitwise builtin instance using the provided MemorySegmentManager.
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

    /// Generates an initial stack elements enforced by this BitwiseBuiltinRunner.
    ///
    /// This function initializes an ArrayList of MaybeRelocatable elements representing the initial stack.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the BitwiseBuiltinRunner instance.
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
        }
        return result;
    }

    /// Retrieve the felt in memory that an address denotes as an integer within the configured `total_n_bits` limit,
    /// default is 251
    /// # Arguments
    /// - address: The address belonging to the Bitwise builtin's segment
    /// - memory: The cairo memory where addresses are looked up
    /// # Returns
    /// The felt as an integer.
    fn getIntWithinBits(self: *const Self, address: Relocatable, memory: *Memory) BitwiseError!u256 {
        // Attempt to retrieve the felt from memory
        const num = memory.getFelt(address) catch return BitwiseError.InvalidAddressForBitwise;

        // Check the number of bits in the felt
        if (num.numBits() > self.bitwise_builtin.total_n_bits) {
            return BitwiseError.UnsupportedNumberOfBits;
        }

        // If the felt fits within the expected amount of bits, return its integer representation
        return num.toInteger();
    }

    /// Deduces the `MemoryCell`, where deduction in the case of Bitwise is a bitwise operation for a given address within the Bitwise runner's memory.
    ///
    /// This function takes an address, and a reference to the memory and returns
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
        // cells per instance are the number of cells per invocation
        // so we are checking here we are orienting the address
        // relative to the allowed 'chunk' of cells
        // this deduction takes place
        const index = address.offset % self.cells_per_instance;

        // relative to that 'chunk'
        // n_input_cells marks the boundary of input memory cells
        // here we are checking that the index isn't pointing
        // to what we designate as input cells
        if (index < self.n_input_cells) {
            return null;
        }

        // we reach 'back' given the index remainder
        // from the initial address to get what is
        // designated as the first input cell, x address
        const x_offset = address.subUint(index) catch {
            return BitwiseError.InvalidBitwiseIndex;
        };
        // and increment from x to get y address
        const y_offset = try x_offset.addUint(1);

        // then we look both up,
        // ensuring the expected bit capacity
        const x = try self.getIntWithinBits(x_offset, memory);
        const y = try self.getIntWithinBits(y_offset, memory);

        // 'where' the address offset points,
        // relative to `cells_per_instance`,
        // dictates which bitwise operation we apply to
        // the input cells
        return MaybeRelocatable.fromInt(
            u256,
            switch (index) {
                2 => x & y, // and
                3 => x ^ y, // xor
                4 => x | y, // or
                else => return BitwiseError.InvalidBitwiseIndex,
            },
        );
    }

    /// Get the number of used cells associated with the BitwiseBuiltinRunner.
    ///
    /// A builtin is given a 'base' segment which it operates
    /// based on its `cells_per_instance.`
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

    /// Retrieves memory segment addresses as a tuple.
    ///
    /// Returns a tuple containing the `base` and `stop_ptr` addresses associated
    /// with the Bitwise runner's memory segments. The `stop_ptr` may be `null`.
    ///
    /// # Returns
    /// A tuple of `usize` and `?usize` addresses.
    pub fn getMemorySegmentAddresses(self: *const Self) Tuple(&.{
        usize,
        ?usize,
    }) {
        return .{
            self.base,
            self.stop_ptr,
        };
    }

    /// Calculates the number of used instances for the BitwiseBuiltinRunner.
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
            self.cells_per_instance,
        );
    }

    /// Retrieves memory access `Relocatable` for the BitwiseBuiltinRunner.
    ///
    /// This function returns an `ArrayList` of `Relocatable` elements, each representing
    /// a memory access within the segment associated with the BitwiseBuiltinRunner's base.
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

    /// Calculates the number of used diluted check units for Bitwise operations.
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
    pub fn getUsedDilutedCheckUnits(self: *Self, allocator: Allocator, diluted_spacing: u32, diluted_n_bits: u32) !usize {
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

        const partition_length = partition.items.len;
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
            const stop_pointer_addr = pointer.subUint(1) catch return RunnerError.NoStopPointer;
            const stop_pointer = try (segments.memory.get(stop_pointer_addr) orelse return RunnerError.NoStopPointer).tryIntoRelocatable();
            if (self.base != stop_pointer.segment_index) {
                return RunnerError.InvalidStopPointerIndex;
            }
            const stop_ptr = stop_pointer.offset;

            if (stop_ptr != try self.getUsedInstances(segments) *
                self.cells_per_instance)
            {
                return RunnerError.InvalidStopPointer;
            }
            self.stop_ptr = stop_ptr;
            return stop_pointer_addr;
        }

        self.stop_ptr = 0;
        return pointer;
    }

    /// Calculates the allocated memory units for the BitwiseBuiltinRunner
    ///
    /// This function determines the memory allocation for the Bitwise runner,
    /// accounting for different layout scenarios.
    /// In cases where `self.ratio` is null, it handles a dynamic layout scenario,
    /// calculating memory based on used cells and instances.
    /// Otherwise, it computes memory units based on the current step and a predefined ratio.
    ///
    /// # Parameters
    ///
    /// - `self`: The current instance of the Bitwise runner.
    /// - `vm`: The Cairo virtual machine instance.
    ///
    /// # Returns
    ///
    ///  Returns the number of memory units as `usize`.
    pub fn getAllocatedMemoryUnits(self: *Self, vm: *CairoVM) !usize {
        // on dynamic layout, ratio would be uninitialized for the builtin
        if (self.ratio == null) {
            // Dynamic layout has the exact number of instances it needs (up to a power of 2).
            const instances = (try self.getUsedCells(vm.segments)) / self.cells_per_instance;
            const components = try std.math.ceilPowerOfTwo(usize, instances / self.instances_per_component);

            return self.cells_per_instance * self.instances_per_component * components;
        }

        const min_step = self.ratio.? * self.instances_per_component;

        if (vm.current_step < min_step) {
            return MemoryError.InsufficientAllocatedCellsErrorMinStepNotReached;
        }

        const value = std.math.divExact(usize, vm.current_step, self.ratio.?) catch return MemoryError.ErrorCalculatingMemoryUnits;

        return self.cells_per_instance * value;
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

test "BitwiseBuiltinRunner: initialStack should return an empty array list if included is false" {
    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer expected.deinit();

    // given a builtin when not included
    var default: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&default, false);

    // then
    var actual = try builtin.initialStack(std.testing.allocator);
    defer actual.deinit();

    try expectEqual(
        expected,
        actual,
    );
}

test "BitwiseBuiltinRunner: initialStack should return an a proper array list if included is true" {
    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try expected.append(.{ .relocatable = .{
        .segment_index = 10,
        .offset = 0,
    } });
    defer expected.deinit();

    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    builtin.base = 10;

    // then
    var actual = try builtin.initialStack(std.testing.allocator);
    defer actual.deinit();

    try expectEqualSlices(
        MaybeRelocatable,
        expected.items,
        actual.items,
    );
}

test "BitwiseBuiltinRunner: initSegments should modify base field of Bitwise builtin" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    const memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    _ = try memory_segment_manager.addSegment();

    // then
    try builtin.initSegments(memory_segment_manager);

    try expectEqual(
        @as(usize, 1),
        builtin.base,
    );
}

test "BitwiseBuiltinRunner: getUsedCells should return memory error if segment used size is null" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    // then
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        builtin.getUsedCells(memory_segment_manager),
    );
}

test "BitwiseBuiltinRunner: getUsedCells should return the number of used cells" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memory_segment_manager.segment_used_sizes.put(0, 10);

    // then
    try expectEqual(
        @as(
            u32,
            10,
        ),
        try builtin.getUsedCells(memory_segment_manager),
    );
}

test "BitwiseBuiltinRunner: getMemorySegmentAddresses should return base and stop pointer" {
    // given
    var builtin = BitwiseBuiltinRunner{};
    // in the case of
    builtin.base = 22;

    try expectEqual(
        @as(
            std.meta.Tuple(&.{ usize, ?usize }),
            .{ 22, null },
        ),
        builtin.getMemorySegmentAddresses(),
    );
}

test "BitwiseBuiltinRunner: getUsedInstances should return memory error if segment used size is null" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    // then
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        builtin.getUsedInstances(memory_segment_manager),
    );
}

test "BitwiseBuiltinRunner: getUsedInstances should return the number of used instances" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memory_segment_manager.segment_used_sizes.put(0, 345);
    // default cells per instance is 5

    // then
    try expectEqual(
        @as(usize, 69),
        try builtin.getUsedInstances(memory_segment_manager),
    );
}

test "BitwiseBuiltinRunner: getMemoryAccesses should return memory error if segment used size is null" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // then
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        builtin.getMemoryAccesses(
            std.testing.allocator,
            &vm,
        ),
    );
}

test "BitwiseBuiltinRunner: getMemoryAccesses should return the memory accesses" {
    var expected = ArrayList(Relocatable).init(std.testing.allocator);
    defer expected.deinit();
    try expected.append(Relocatable{
        .segment_index = 5,
        .offset = 0,
    });
    try expected.append(Relocatable{
        .segment_index = 5,
        .offset = 1,
    });
    try expected.append(Relocatable{
        .segment_index = 5,
        .offset = 2,
    });
    try expected.append(Relocatable{
        .segment_index = 5,
        .offset = 3,
    });

    // given
    var builtin = BitwiseBuiltinRunner{};
    // in the case of
    builtin.base = 5;

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(5, 4);

    var actual = try builtin.getMemoryAccesses(
        std.testing.allocator,
        &vm,
    );
    defer actual.deinit();
    try expectEqualSlices(
        Relocatable,
        expected.items,
        actual.items,
    );
}

test "BitwiseBuiltinRunner: getUsedDilutedCheckUnits should pass  test cases" {
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
        var builtin = BitwiseBuiltinRunner{};
        const allocator = std.testing.allocator;

        // when
        const result = try builtin.getUsedDilutedCheckUnits(allocator, case.when.diluted_spacing, case.when.diluted_n_bits);

        // then
        try expectEqual(@as(usize, case.then), result);
    }
}

test "BitwiseBuiltinRunner: getAllocatedMemoryUnits should return expected memory units with ratio" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    vm.current_step = 256;
    // then
    try expectEqual(
        @as(usize, 5),
        try builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BitwiseBuiltinRunner: getAllocatedMemoryUnits should throw MemoryError.MissingSegmentUsedSizes without ratio and no used cells" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // in the case of
    builtin.ratio = null;

    // default instances per component -> 1
    // default cells per instance -> 5
    // used is the amount of cells the base segment has

    // instance is used / cell per instance
    // components is instances divided by instances per component
    // to the next power of two

    // expected should be 5 * 1 * components

    // then
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BitwiseBuiltinRunner: getAllocatedMemoryUnits should return expected memory units without ratio" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // in the case of
    builtin.ratio = null;

    // when

    // default instances per component -> 1
    // default cells per instance -> 5
    // used is the amount of cells the base segment has
    // -> 10
    try vm.segments.segment_used_sizes.put(0, 10);

    // instances is used / cell per instance
    // -> (2)
    // components is instances divided by instances per component
    // -> (2)
    // to the next power of two
    // (or the same if value is a power of 2)
    // -> (2)

    // expected should be 5 * 1 * 2
    // -> 10

    // then
    try expectEqual(
        @as(usize, 10),
        try builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BitwiseBuiltinRunner: getAllocatedMemoryUnits should fail with MemoryError.InsufficientAllocatedCellsErrorMinStepNotReached when minimum step threshold is not met" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // min step is ratio * instance_per_component
    // where
    // default ratio is 256
    // default instance_per_component is 1
    // when
    vm.current_step = 255;
    // then
    try expectError(
        MemoryError.InsufficientAllocatedCellsErrorMinStepNotReached,
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BitwiseBuiltinRunner: getAllocatedMemoryUnits should fail with MemoryError.ErrorCalculatingMemoryUnits when vm step cannot divide exactly into builtin ratio" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // where
    // default ratio is 256

    vm.current_step = 257;
    // then
    try expectError(
        MemoryError.ErrorCalculatingMemoryUnits,
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BitwiseBuiltinRunner: should return expected result for deduceMemoryCell bitwise-and" {
    // given
    var builtin = BitwiseBuiltinRunner{};

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
    const expected = MaybeRelocatable{ .felt = Felt252.fromInt(u8, 8) };

    // then
    const result = try builtin.deduceMemoryCell(address, mem);

    try expectEqual(
        expected,
        result.?,
    );
}

test "BitwiseBuiltinRunner: should return expected result for deduceMemoryCell bitwise-xor" {
    // given
    var builtin = BitwiseBuiltinRunner{};

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
    const expected = MaybeRelocatable{ .felt = Felt252.fromInt(u8, 6) };

    // then
    const result = try builtin.deduceMemoryCell(address, mem);

    try expectEqual(
        expected,
        result.?,
    );
}

test "BitwiseBuiltinRunner: should return expectededuceMemoryCell bitwise-or" {
    // given
    var builtin = BitwiseBuiltinRunner{};

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
    const expected = MaybeRelocatable{ .felt = Felt252.fromInt(u8, 14) };

    // then
    const result = try builtin.deduceMemoryCell(address, mem);
    try expectEqual(
        expected,
        result.?,
    );
}

test "BitwiseBuiltinRunner: finalStack should return relocatable pointer if not included" {
    // given
    var default: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&default, false);

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    // then
    try expectEqual(
        Relocatable.init(
            2,
            2,
        ),
        try builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "BitwiseBuiltinRunner: finalStack should return NoStopPointer error if pointer offset is 0" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    // then
    try expectError(
        RunnerError.NoStopPointer,
        builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 0),
        ),
    );
}

test "BitwiseBuiltinRunner: finalStack should return NoStopPointer error if no data in memory at the given stop pointer address" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    // then
    try expectError(
        RunnerError.NoStopPointer,
        builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "BitwiseBuiltinRunner: finalStack should return TypeMismatchNotRelocatable error if data in memory at the given stop pointer address is not Relocatable" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // when
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();
    _ = try memory_segment_manager.addSegment();

    // then
    try memory_segment_manager.memory.set(
        std.testing.allocator,
        try Relocatable.init(
            2,
            2,
        ).subUint(@intCast(1)),
        .{ .felt = Felt252.fromInt(u8, 10) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // then
    try expectError(
        CairoVMError.TypeMismatchNotRelocatable,
        builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "BitwiseBuiltinRunner: finalStack should return InvalidStopPointerIndex error if segment index of stop pointer is not BitwiseBuiltinRunner base" {

    // given
    var builtin = BitwiseBuiltinRunner{};

    // in the case of
    builtin.base = 22;

    // when
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
        ).subUint(@intCast(1)),
        .{ .relocatable = Relocatable.init(
            10,
            2,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // then
    try expectError(
        RunnerError.InvalidStopPointerIndex,
        builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "BitwiseBuiltinRunner: finalStack should return InvalidStopPointer error if stop pointer offset is not cells used" {
    // given
    var builtin = BitwiseBuiltinRunner{};
    // in the case of
    builtin.base = 22;

    // when
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
        ).subUint(@intCast(1)),
        .{ .relocatable = Relocatable.init(
            22,
            2,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.segment_used_sizes.put(22, 345);

    // then
    try expectError(
        RunnerError.InvalidStopPointer,
        builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );
}

test "BitwiseBuiltinRunner: finalStack should return stop pointer address and update stop_ptr" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    // in the case of
    builtin.base = 22;

    // when
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
        ).subUint(@intCast(1)),
        .{ .relocatable = Relocatable.init(
            22,
            345,
        ) },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try memory_segment_manager.segment_used_sizes.put(22, 345);

    // then
    try expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(
            memory_segment_manager,
            Relocatable.init(2, 2),
        ),
    );

    try expectEqual(
        @as(?usize, @intCast(345)),
        builtin.stop_ptr.?,
    );
}

test "BitwiseBuiltinRunner: getAllocatedMemoryUnits should return InsufficientAllocatedCellsErrorMinStepNotReached" {
    // given
    var builtin = BitwiseBuiltinRunner{};

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // then
    try expectError(
        MemoryError.InsufficientAllocatedCellsErrorMinStepNotReached,
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BitwiseBuiltinRunner: deduceMemoryCell when address.offset is outside input cell length should return null" {
    // given
    var builtin = BitwiseBuiltinRunner{};

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

test "BitwiseBuiltinRunner: deduceMemoryCell when address points to nothing in memory should return null" {
    // given
    var builtin = BitwiseBuiltinRunner{};

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
    var builtin = BitwiseBuiltinRunner{};

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
    var builtin = BitwiseBuiltinRunner{};

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
