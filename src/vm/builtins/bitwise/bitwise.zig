// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;

// Local imports.
const Memory = @import("../../memory/memory.zig").Memory;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const fromFelt = @import("../../memory/relocatable.zig").fromFelt;
const newFromRelocatable = @import("../../memory/relocatable.zig").newFromRelocatable;
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;

// *****************************************************************************
// *                       CUSTOM ERROR TYPE                                   *
// *****************************************************************************

// Error type to represent different error conditions during bitwise builtin.
pub const Error = error{ InvalidBitwiseIndex, UnsupportedNumberOfBits, InvalidAddressForBitwise };

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
fn getValue(address: Relocatable, memory: *Memory) Error!u256 {
    var value = memory.get(address) catch {
        return Error.InvalidAddressForBitwise;
    };

    var felt = value.tryIntoFelt() catch {
        return Error.InvalidAddressForBitwise;
    };

    if (felt.toInteger() > std.math.pow(u256, 2, BITWISE_TOTAL_N_BITS)) {
        return Error.UnsupportedNumberOfBits;
    }

    return felt.toInteger();
}

/// Compute the auto-deduction rule for Bitwise
/// # Arguments
/// - address: The address belonging to the Bitwise builtin's segment
/// - memory: The cairo memory where addresses are looked up
/// # Returns
/// The deduced value as a `MaybeRelocatable`
pub fn deduce(address: Relocatable, memory: *Memory) Error!MaybeRelocatable {
    const index = address.offset % CELLS_PER_BITWISE;

    if (index < BITWISE_INPUT_CELLS_PER_INSTANCE) {
        return Error.InvalidBitwiseIndex;
    }

    // calculate offset
    const x_offset = address.subUint(index) catch {
        return Error.InvalidBitwiseIndex;
    };
    const y_offset = try x_offset.addUint(1);

    var x = try getValue(x_offset, memory);
    var y = try getValue(y_offset, memory);

    var res = switch (index) {
        2 => x & y, // and
        3 => x ^ y, // xor
        4 => x | y, // or
        else => return Error.InvalidBitwiseIndex,
    };

    return MaybeRelocatable{ .felt = Felt252.fromInteger(res) };
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "deduce when address.offset less than BITWISE_INPUT_CELLS_PER_INSTANCE" {

    // given
    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    var address = Relocatable.new(0, 5);

    // then
    try expectError(Error.InvalidBitwiseIndex, deduce(address, mem));
}

test "deduce when address points to nothing in memory" {

    // given
    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    var address = Relocatable.new(0, 3);

    // then
    try expectError(Error.InvalidAddressForBitwise, deduce(address, mem));
}

test "deduce when address points to relocatable variant of MaybeRelocatable " {

    // given
    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    var address = Relocatable.new(0, 3);

    try mem.set(Relocatable.new(0, 5), newFromRelocatable(address));

    // then
    try expectError(Error.InvalidAddressForBitwise, deduce(address, mem));
}

test "deduce when address points to felt greater than BITWISE_TOTAL_N_BITS" {

    // given
    const number = std.math.pow(u256, 2, BITWISE_TOTAL_N_BITS) + 1;
    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    var address = Relocatable.new(0, 3);

    try mem.set(Relocatable.new(0, 0), fromFelt(Felt252.fromInteger(number)));

    // then
    try expectError(Error.UnsupportedNumberOfBits, deduce(address, mem));
}

// happy path tests graciously ported from https://github.com/lambdaclass/cairo-vm_in_go/blob/main/pkg/builtins/bitwise_test.go#L13
test "valid bitwise and" {

    // given
    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    try mem.set(Relocatable.new(0, 5), fromFelt(Felt252.fromInteger(10)));
    try mem.set(Relocatable.new(0, 6), fromFelt(Felt252.fromInteger(12)));
    try mem.set(Relocatable.new(0, 7), fromFelt(Felt252.fromInteger(0)));

    var address = Relocatable.new(0, 7);
    var expected = MaybeRelocatable{ .felt = Felt252.fromInteger(8) };

    // then
    var result = deduce(address, mem);
    try expectEqual(result, expected);
}

test "valid bitwise xor" {

    // given
    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    try mem.set(Relocatable.new(0, 5), fromFelt(Felt252.fromInteger(10)));
    try mem.set(Relocatable.new(0, 6), fromFelt(Felt252.fromInteger(12)));
    try mem.set(Relocatable.new(0, 8), fromFelt(Felt252.fromInteger(0)));

    var address = Relocatable.new(0, 8);
    var expected = MaybeRelocatable{ .felt = Felt252.fromInteger(6) };

    // then
    var result = deduce(address, mem);
    try expectEqual(result, expected);
}

test "valid bitwise or" {

    // given
    var allocator = std.testing.allocator;
    var mem = try Memory.init(allocator);
    defer mem.deinit();

    // when
    try mem.set(Relocatable.new(0, 5), fromFelt(Felt252.fromInteger(10)));
    try mem.set(Relocatable.new(0, 6), fromFelt(Felt252.fromInteger(12)));
    try mem.set(Relocatable.new(0, 9), fromFelt(Felt252.fromInteger(0)));

    var address = Relocatable.new(0, 9);
    var expected = MaybeRelocatable{ .felt = Felt252.fromInteger(14) };

    // then
    var result = deduce(address, mem);
    try expectEqual(result, expected);
}
