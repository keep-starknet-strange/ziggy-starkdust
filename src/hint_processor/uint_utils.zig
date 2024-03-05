// pub(crate) fn split<const N: usize>(num: &BigUint, num_bits_shift: u32) -> [Felt252; N] {
//     let mut num = num.clone();
//     let bitmask = &((BigUint::one() << num_bits_shift) - 1_u32);
//     [0; N].map(|_| {
//         let a = &num & bitmask;
//         num >>= num_bits_shift;
//         Felt252::from(&a)
//     })
// }

// pub(crate) fn pack<const N: usize>(
//     limbs: [impl AsRef<Felt252>; N],
//     num_bits_shift: usize,
// ) -> BigUint {
//     limbs
//         .into_iter()
//         .enumerate()
//         .map(|(i, limb)| limb.as_ref().to_biguint() << (i * num_bits_shift))
//         .sum()
// }
const std = @import("std");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;

pub fn split(comptime T: type, num: T, N: usize, num_bits_shift: u32) [N]Felt252 {
    var temp_num = num;
    const bitmask = (T(1) << num_bits_shift) - T(1); // Ensure bitmask is of type T.
    const result: [N]Felt252 = undefined;

    for (result) |limb| {
        const a = temp_num & bitmask;
        temp_num >>= num_bits_shift;
        limb = Felt252(a);
    }
    return result;
}

pub fn pack(comptime T: type, N: usize, limbs: [N]T, num_bits_shift: usize) T {
    var result: T = 0;
    for (0.., limbs) |i, limb| {
        result += limb << (i * num_bits_shift);
    }
    return result;
}
