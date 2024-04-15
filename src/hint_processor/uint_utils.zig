const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const fromBigInt = @import("../math/fields/starknet.zig").fromBigInt;
const Int = @import("std").math.big.int.Managed;
const testing = std.testing;

pub fn split(allocator: std.mem.Allocator, num: Int, comptime N: usize, num_bits_shift: usize) ![N]Felt252 {
    var temp_num: Int = try num.clone();
    defer temp_num.deinit();

    var bitmask = try Int.initSet(allocator, 1);
    defer bitmask.deinit();

    try bitmask.shiftLeft(&bitmask, num_bits_shift);
    try bitmask.addScalar(&bitmask, -1);

    var shifted = try Int.init(allocator);
    defer shifted.deinit();

    var result: [N]Felt252 = undefined;

    for (&result) |*r| {
        try shifted.bitAnd(&temp_num, &bitmask);
        // TODO: bug in zig with shift more than 64, when new zig build will be avaialable with this commit 7cc0e6d4cd5d699d5377cf47ee27a2e089d046bf
        for (0..num_bits_shift / 64) |_|
            try temp_num.shiftRight(&temp_num, 63);
        try temp_num.shiftRight(&temp_num, num_bits_shift % 63);

        r.* = try fromBigInt(allocator, shifted);
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
