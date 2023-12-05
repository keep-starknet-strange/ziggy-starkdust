const std = @import("std");

const bitwise_instance_def = @import("../../types/bitwise_instance_def.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const memoryFile = @import("../../memory/memory.zig");
const Memory = memoryFile.Memory;
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;

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

    /// Retrieve the felt in memory that an address denotes as an integer.
    /// # Arguments
    /// - address: The address belonging to the Bitwise builtin's segment
    /// - memory: The cairo memory where addresses are looked up
    /// # Returns
    /// The felt as an integer.
    fn getFeltInRange(self: Self, address: Relocatable, memory: *Memory) BitwiseError!u256 {
        const value = (memory.getFelt(address) catch return BitwiseError.InvalidAddressForBitwise).toInteger();

        if (value > std.math.pow(u256, 2, self.bitwise_builtin.total_n_bits)) {
            return BitwiseError.UnsupportedNumberOfBits;
        }

        return value;
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

    pub fn deduceMemoryCell(
        self: *const Self,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        const index = address.offset % self.cells_per_instance;

        if (index < self.n_input_cells) {
            return BitwiseError.InvalidBitwiseIndex;
        }

        // calculate offset
        const x_offset = address.subUint(index) catch {
            return BitwiseError.InvalidBitwiseIndex;
        };
        const y_offset = try x_offset.addUint(1);

        var x = try self.getFeltInRange(x_offset, memory);
        var y = try self.getFeltInRange(y_offset, memory);

        var res = switch (index) {
            2 => x & y, // and
            3 => x ^ y, // xor
            4 => x | y, // or
            else => return BitwiseError.InvalidBitwiseIndex,
        };

        return MaybeRelocatable{ .felt = Felt252.fromInteger(res) };
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "deduce when address.offset less than BITWISE_INPUT_CELLS_PER_INSTANCE" {

    // given
    var instance_def: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&instance_def, true);

    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    var address = Relocatable.new(0, 5);

    // then
    try expectError(BitwiseError.InvalidBitwiseIndex, builtin.deduceMemoryCell(address, mem));
}

test "deduce when address points to nothing in memory" {

    // given
    var instance_def: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&instance_def, true);

    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    var address = Relocatable.new(0, 3);

    // then
    try expectError(BitwiseError.InvalidAddressForBitwise, builtin.deduceMemoryCell(address, mem));
}

test "deduce when address points to relocatable variant of MaybeRelocatable " {

    // given
    var instance_def: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&instance_def, true);

    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);
    // when
    var address = Relocatable.new(0, 3);

    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{
            .{ .{ 0, 3 }, .{ 0, 3 } },
        },
    );

    // then
    try expectError(BitwiseError.InvalidAddressForBitwise, builtin.deduceMemoryCell(address, mem));
}

test "deduce when address points to felt greater than BITWISE_TOTAL_N_BITS" {

    // given
    var instance_def: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&instance_def, true);

    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);
    // when
    var address = Relocatable.new(0, 7);

    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{ .{ .{ 0, 5 }, .{std.math.pow(u256, 2, 251) + 1} }, .{ .{ 0, 6 }, .{12} }, .{ .{ 0, 8 }, .{0} } },
    );

    // then
    try expectError(BitwiseError.UnsupportedNumberOfBits, builtin.deduceMemoryCell(address, mem));
}

// happy path tests graciously ported from https://github.com/lambdaclass/cairo-vm_in_go/blob/main/pkg/builtins/bitwise_test.go#L13
test "valid bitwise and" {

    // given
    var instance_def: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&instance_def, true);

    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);

    // when
    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{ .{ .{ 0, 5 }, .{10} }, .{ .{ 0, 6 }, .{12} }, .{ .{ 0, 8 }, .{0} } },
    );

    var address = Relocatable.new(0, 7);
    var expected = MaybeRelocatable{ .felt = Felt252.fromInteger(8) };

    // then
    var result = try builtin.deduceMemoryCell(address, mem);
    try expectEqual(
        expected,
        result.?,
    );
}

test "valid bitwise xor" {

    // given
    var instance_def: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&instance_def, true);

    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);

    // when
    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{ .{ .{ 0, 5 }, .{10} }, .{ .{ 0, 6 }, .{12} }, .{ .{ 0, 8 }, .{0} } },
    );

    var address = Relocatable.new(0, 8);
    var expected = MaybeRelocatable{ .felt = Felt252.fromInteger(6) };

    // then
    var result = try builtin.deduceMemoryCell(address, mem);
    try expectEqual(
        expected,
        result.?,
    );
}

test "valid bitwise or" {

    // given
    var instance_def: bitwise_instance_def.BitwiseInstanceDef = .{};
    var builtin = BitwiseBuiltinRunner.init(&instance_def, true);

    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();
    defer mem.deinitData(allocator);

    // when
    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{ .{ .{ 0, 5 }, .{10} }, .{ .{ 0, 6 }, .{12} }, .{ .{ 0, 8 }, .{0} } },
    );

    var address = Relocatable.new(0, 9);
    var expected = MaybeRelocatable{ .felt = Felt252.fromInteger(14) };

    // then
    var result = try builtin.deduceMemoryCell(address, mem);
    try expectEqual(
        expected,
        result.?,
    );
}
