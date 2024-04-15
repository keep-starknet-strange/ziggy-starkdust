const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const Int = @import("std").math.big.int.Managed;
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
    errdefer result.deinit();
    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    for (0..N) |i| {
        try tmp.set(limbs[i].toInteger());

        try tmp.shiftLeft(&tmp, num_bits_shift * i);

        try result.add(&result, &tmp);
    }

    return result;
}

test "UintUtils: split64 with uint utils" {
    var num = try Int.initSet(testing.allocator, 850981239023189021389081239089023);
    defer num.deinit();
    const limbs = try split(testing.allocator, num, 2, 64);

    try std.testing.expectEqualSlices(Felt252, &[2]Felt252{ Felt252.fromInt(u64, 7249717543555297151), Felt252.fromInt(u64, 46131785404667) }, &limbs);
}

test "UintUtils: u384 split128 with uint utils" {
    var num = try Int.initSet(testing.allocator, 6805647338418769269267492148635364229100);
    defer num.deinit();
    const limbs = try split(testing.allocator, num, 2, 128);
    try std.testing.expectEqualSlices(Felt252, &[2]Felt252{ Felt252.fromInt(u128, 340282366920938463463374607431768211436), Felt252.fromInt(u128, 19) }, &limbs);
}

test "UintUtils: pack 64 with uint utils" {
    const limbs = [2]Felt252{ Felt252.fromInt(u64, 7249717543555297151), Felt252.fromInt(u64, 46131785404667) };
    var num = try pack(testing.allocator, 2, limbs, 64);
    defer num.deinit();
    var expected = try Int.initSet(testing.allocator, 850981239023189021389081239089023);
    defer expected.deinit();
    try std.testing.expectEqualSlices(usize, expected.limbs, num.limbs);
}

test "UintUtils: pack 128 with uint utils" {
    const limbs = [2]Felt252{ Felt252.fromInt(u128, 59784002098951797857788619418398833806), Felt252.fromInt(u128, 1) };
    var num = try pack(testing.allocator, 2, limbs, 128);
    defer num.deinit();
    var expected = try Int.initSet(testing.allocator, 400066369019890261321163226850167045262);
    defer expected.deinit();
    try std.testing.expectEqualSlices(usize, expected.limbs, num.limbs);
}
