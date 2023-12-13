const std = @import("std");
const Felt252 = @import("../fields/starknet.zig").Felt252;
const expectEqual = std.testing.expectEqual;

const starknet_crypto = @cImport(@cInclude("starknet_crypto.h"));

pub fn pedersenHash(a: Felt252, b: Felt252) Felt252 {
    // convert Felt252 to big endian byte array
    var a_bytes = a.toBytesBe();
    var b_bytes = b.toBytesBe();
    var res = [_]u8{0} ** 32;
    // pedersen hash needs the representation in Big endian
    starknet_crypto.pedersen_hash(&a_bytes[0], &b_bytes[0], &res[0]);
    // pedersen hash stores a big endian byte array in res
    return Felt252.fromBytesBe(res);
}

test "pedersen_p" {
    try expectEqual(Felt252.fromInteger(0x49ee3eba8c1600700ee1b87eb599f16716b0b1022947733551fde4050ca6804), pedersenHash(Felt252.zero(), Felt252.zero()));
    try expectEqual(Felt252.fromInteger(0x30e480bed5fe53fa909cc0f8c4d99b8f9f2c016be4c41e13a4848797979c662), pedersenHash(Felt252.fromInteger(0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb), Felt252.fromInteger(0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a)));
}
