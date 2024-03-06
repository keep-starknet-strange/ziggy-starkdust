const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;

// Rewrite split in Zig
pub fn split(num: u512, comptime N: usize, num_bits_shift: u32) [N]Felt252 {
    var temp_num = num;
    var result: [N]Felt252 = undefined;
    for (0..N) |i| {
        const bitmask = (@as(u512, 1) << @intCast(num_bits_shift)) - 1;
        const shifted = temp_num & bitmask;
        result[i] = Felt252.fromInt(u512, shifted);
        temp_num >>= @intCast(num_bits_shift);
    }
    return result;
}

// pub fn pack(comptime T: type, N: usize, limbs: [N]Felt252, num_bits_shift: usize) T {
//     var result: T = 0;
//     for (0.., limbs) |i, limb| {
//         result += limb << (i * num_bits_shift);
//     }
//     return result;
// }
