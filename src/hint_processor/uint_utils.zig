const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const Int = std.math.big.int.Managed;
pub fn split(num: Int, comptime N: usize, num_bits_shift: usize) ![N]Felt252 {
    const allocator = std.heap.page_allocator;
    const one = try Int.initSet(allocator, 1);

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
    const allocator = std.testing.allocator;
    var num = try Int.initSet(allocator, 850981239023189021389081239089023);
    defer num.deinit();
    const limbs = try split(num, 4, 64);
    try std.testing.expectEqual(Felt252.fromInt(u64, 7249717543555297151), limbs[0]);
    try std.testing.expectEqual(Felt252.fromInt(u64, 46131785404667), limbs[1]);
    try std.testing.expectEqual(Felt252.fromInt(u64, 0), limbs[2]);
    try std.testing.expectEqual(Felt252.fromInt(u64, 0), limbs[3]);
}
