const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const Int = @import("std").math.big.int.Managed;

pub fn pack(limbs: []const Felt252, num_bits_shift: usize) u256 {
    var result: u256 = 0;
    for (0..limbs.len) |i| {
        result += limbs[i].toInteger() << (i * num_bits_shift);
    }
    return result;
}

pub fn split(comptime N: usize, num: Int, num_bits_shift: u32) [N]Felt252 {
    var num_copy = num;
    const bitmask = ((1 << num_bits_shift) - 1);
    const result: [N]Felt252 = undefined;
    for (result) |r| {
        r.* = Felt252.fromInt(num_copy & bitmask);
        num_copy >>= num_bits_shift;
    }
    return result;
}
const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const Int = std.math.big.int.Managed;
const testing = std.testing;

pub fn split(allocator: std.mem.Allocator, num: Int, comptime N: usize, num_bits_shift: usize) ![N]Felt252 {
    var one = try Int.initSet(allocator, 1);
    defer one.deinit();
    var temp_num: Int = try num.clone();
    defer temp_num.deinit();

    var bitmask = try Int.initSet(allocator, 1);
    defer bitmask.deinit();
    try bitmask.shiftLeft(&bitmask, num_bits_shift);
    try bitmask.sub(&bitmask, &one);

    var shifted = try Int.init(allocator);
    defer shifted.deinit();

    var result: [N]Felt252 = undefined;
    for (&result) |*r| {
        try shifted.bitAnd(&temp_num, &bitmask);
        r.* = Felt252.fromInt(u256, try shifted.to(u256));
        try temp_num.shiftRight(&temp_num, num_bits_shift);
    }
    return result;
}

pub fn pack(allocator: std.mem.Allocator, comptime N: usize, limbs: [N]Felt252, num_bits_shift: usize) !Int {
    var result = try Int.init(allocator);

    for (0..N) |i| {
        var limb_to_uint = try Int.initSet(allocator, limbs[i].toInteger());
        defer limb_to_uint.deinit();
        try limb_to_uint.shiftLeft(&limb_to_uint, num_bits_shift * i);
        try result.add(&result, &limb_to_uint);
    }
    return result;
}
test "split64 with uint utils" {
    var num = try Int.initSet(testing.allocator, 850981239023189021389081239089023);
    defer num.deinit();
    const limbs = try split(testing.allocator, num, 2, 64);

    try std.testing.expectEqualSlices(Felt252, &[2]Felt252{ Felt252.fromInt(u64, 7249717543555297151), Felt252.fromInt(u64, 46131785404667) }, &limbs);
}

test "u384 split128 with uint utils" {
    var num = try Int.initSet(testing.allocator, 6805647338418769269267492148635364229100);
    defer num.deinit();
    const limbs = try split(testing.allocator, num, 2, 128);
    try std.testing.expectEqualSlices(Felt252, &[2]Felt252{ Felt252.fromInt(u128, 340282366920938463463374607431768211436), Felt252.fromInt(u128, 19) }, &limbs);
}

test "pack 64 with uint utils" {
    const limbs = [2]Felt252{ Felt252.fromInt(u64, 7249717543555297151), Felt252.fromInt(u64, 46131785404667) };
    var num = try pack(testing.allocator, 2, limbs, 64);
    defer num.deinit();
    var expected = try Int.initSet(testing.allocator, 850981239023189021389081239089023);
    defer expected.deinit();
    try std.testing.expectEqualSlices(usize, expected.limbs, num.limbs);
}

test "pack 128 with uint utils" {
    const limbs = [2]Felt252{ Felt252.fromInt(u128, 59784002098951797857788619418398833806), Felt252.fromInt(u128, 1) };
    var num = try pack(testing.allocator, 2, limbs, 128);
    defer num.deinit();
    var expected = try Int.initSet(testing.allocator, 400066369019890261321163226850167045262);
    defer expected.deinit();
    try std.testing.expectEqualSlices(usize, expected.limbs, num.limbs);
}
