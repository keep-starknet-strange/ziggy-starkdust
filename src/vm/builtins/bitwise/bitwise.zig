// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;

// Local imports.
const memoryFile = @import("../../memory/memory.zig");
const Memory = @import("../../memory/memory.zig").Memory;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const fromFelt = @import("../../memory/relocatable.zig").fromFelt;
const fromU256 = @import("../../memory/relocatable.zig").fromU256;
const newFromRelocatable = @import("../../memory/relocatable.zig").newFromRelocatable;
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;

// *****************************************************************************
// *                       CUSTOM ERROR TYPE                                   *
// *****************************************************************************

// Error type to represent different error conditions during bitwise builtin.
pub const BitwiseError = error{
    InvalidBitwiseIndex,
    UnsupportedNumberOfBits,
    InvalidAddressForBitwise,
};

/// Each bitwise operation consists of 5 cells (two inputs and three outputs - and, or, xor).
// comment credit to: https://github.com/starkware-libs/cairo-lang/blob//src/starkware/cairo/lang/builtins/bitwise/instance_def.py#L4
const CELLS_PER_BITWISE: u64 = 5;
/// The number of bits in a single field element that are supported by the bitwise builtin.
const BITWISE_TOTAL_N_BITS = 251;
const BITWISE_INPUT_CELLS_PER_INSTANCE = 2;

/// Retrieve the felt in memory that an address denotes as an integer.
/// # Arguments
/// - address: The address belonging to the Bitwise builtin's segment
/// - memory: The cairo memory where addresses are looked up
/// # Returns
/// The felt as an integer.
fn getValue(address: Relocatable, memory: *Memory) BitwiseError!u256 {
    const value = memory.get(address) catch {
        return BitwiseError.InvalidAddressForBitwise;
    };

    if (value) |v| {
        var felt = v.tryIntoFelt() catch {
            return BitwiseError.InvalidAddressForBitwise;
        };

        if (felt.toInteger() > std.math.pow(u256, 2, BITWISE_TOTAL_N_BITS)) {
            return BitwiseError.UnsupportedNumberOfBits;
        }

        return felt.toInteger();
    }

    return BitwiseError.InvalidAddressForBitwise;
}

/// Compute the auto-deduction rule for Bitwise
/// # Arguments
/// - address: The address belonging to the Bitwise builtin's segment
/// - memory: The cairo memory where addresses are looked up
/// # Returns
/// The deduced value as a `MaybeRelocatable`
pub fn deduce(address: Relocatable, memory: *Memory) BitwiseError!MaybeRelocatable {
    const index = address.offset % CELLS_PER_BITWISE;

    if (index < BITWISE_INPUT_CELLS_PER_INSTANCE) {
        return BitwiseError.InvalidBitwiseIndex;
    }

    // calculate offset
    const x_offset = address.subUint(index) catch {
        return BitwiseError.InvalidBitwiseIndex;
    };
    const y_offset = try x_offset.addUint(1);

    const x = try getValue(x_offset, memory);
    const y = try getValue(y_offset, memory);

    const res = switch (index) {
        2 => x & y, // and
        3 => x ^ y, // xor
        4 => x | y, // or
        else => return BitwiseError.InvalidBitwiseIndex,
    };

    return fromU256(res);
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "deduce when address.offset less than BITWISE_INPUT_CELLS_PER_INSTANCE" {

    // given
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    const address = Relocatable.new(0, 5);

    // then
    try expectError(BitwiseError.InvalidBitwiseIndex, deduce(address, mem));
}

test "deduce when address points to nothing in memory" {

    // given
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    const address = Relocatable.new(0, 3);

    // then
    try expectError(BitwiseError.InvalidAddressForBitwise, deduce(address, mem));
}

test "deduce when address points to relocatable variant of MaybeRelocatable " {

    // given
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    const address = Relocatable.new(0, 3);

    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{.{ .{ 0, 5 }, .{ 0, 3 } }},
    );
    defer mem.deinitData(std.testing.allocator);

    // then
    try expectError(BitwiseError.InvalidAddressForBitwise, deduce(address, mem));
}

test "deduce when address points to felt greater than BITWISE_TOTAL_N_BITS" {

    // given
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    const address = Relocatable.new(0, 3);

    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{std.math.pow(u256, 2, BITWISE_TOTAL_N_BITS) + 1} }},
    );
    defer mem.deinitData(std.testing.allocator);

    // then
    try expectError(BitwiseError.UnsupportedNumberOfBits, deduce(address, mem));
}

// happy path tests graciously ported from https://github.com/lambdaclass/cairo-vm_in_go/blob/main/pkg/builtins/bitwise_test.go#L13
test "valid bitwise and" {

    // given
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{
            .{ .{ 0, 5 }, .{10} },
            .{ .{ 0, 6 }, .{12} },
            .{ .{ 0, 7 }, .{0} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    const address = Relocatable.new(0, 7);
    const expected = fromU256(8);

    // then
    const result = try deduce(address, mem);
    try expectEqual(
        expected,
        result,
    );
}

test "valid bitwise xor" {

    // given
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{
            .{ .{ 0, 5 }, .{10} },
            .{ .{ 0, 6 }, .{12} },
            .{ .{ 0, 8 }, .{0} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    const address = Relocatable.new(0, 8);
    const expected = fromU256(6);

    // then
    const result = try deduce(address, mem);
    try expectEqual(
        expected,
        result,
    );
}

test "valid bitwise or" {

    // given
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    try memoryFile.setUpMemory(
        mem,
        std.testing.allocator,
        .{
            .{ .{ 0, 5 }, .{10} },
            .{ .{ 0, 6 }, .{12} },
            .{ .{ 0, 9 }, .{0} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    const address = Relocatable.new(0, 9);
    const expected = fromU256(14);

    // then
    const result = try deduce(address, mem);
    try expectEqual(
        expected,
        result,
    );
}
