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

test "uint256 split64 with uint utils" {
    var num = try Int.initSet(testing.allocator, 850981239023189021389081239089023);
    defer num.deinit();
    const limbs = try split(testing.allocator, num, 2, 64);

    try std.testing.expectEqualSlices(Felt252, &[2]Felt252{ Felt252.fromInt(u64, 7249717543555297151), Felt252.fromInt(u64, 46131785404667) }, &limbs);
}

test "uint256 split64 with big a" {
    var num = try Int.initSet(testing.allocator, 400066369019890261321163226850167045262);
    defer num.deinit();
    const limbs = try split(testing.allocator, num, 2, 128);

    try std.testing.expectEqualSlices(Felt252, &[2]Felt252{ Felt252.fromInt(u128, 59784002098951797857788619418398833806), Felt252.fromInt(u64, 1) }, &limbs);
}
