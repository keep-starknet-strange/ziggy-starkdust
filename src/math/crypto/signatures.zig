const std = @import("std");
const Felt252 = @import("../fields/starknet.zig").Felt252;
const ProjectivePoint = @import("../crypto/curve/ec_point.zig").ProjectivePoint;
const AffinePoint = @import("../crypto/curve/ec_point.zig").AffinePoint;

const EC_ORDER = @import("../crypto/curve/curve_params.zig").EC_ORDER;
const GENERATOR = @import("../crypto/curve/curve_params.zig").GENERATOR;
const ELEMENT_UPPER_BOUND: Felt252 = .{
    .fe = [4]u64{
        18446743986131435553,
        160989183,
        18446744073709255680,
        576459263475450960,
    },
};

/// Stark ECDSA signature
pub const Signature = struct {
    const Self = @This();

    /// The `r` value of a signature
    r: Felt252,
    /// The `s` value of a signature
    s: Felt252,
};

/// Stark ECDSA signature
pub const ExtendedSignature = struct {
    const Self = @This();

    /// The `r` value of a signature
    r: Felt252,
    /// The `s` value of a signature
    s: Felt252,
    /// The `v` value of a signature
    v: Felt252,
};

pub const SignError = error{
    InvalidMessageHash,
    InvalidK,
};

fn mulByBits(x: AffinePoint, y: Felt252) AffinePoint {
    const z = ProjectivePoint.fromAffinePoint(x).mulByBits(y.toBitsLe());
    return AffinePoint.fromProjectivePoint(z);
}
/// Computes ECDSA signature given a Stark private key and message hash.
///
/// ### Arguments
///
/// * `private_key`: The private key
/// * `message`: The message hash
/// * `k`: A random `k` value. You **MUST NOT** use the same `k` on different signatures
pub fn sign(private_key: Felt252, message: Felt252, k: Felt252) !ExtendedSignature {
    if (message.ge(ELEMENT_UPPER_BOUND)) {
        return SignError.InvalidMessageHash;
    }

    if (k.isZero()) {
        return SignError.InvalidK;
    }

    const full_r = mulByBits(GENERATOR, k);
    const r = full_r.x;

    if (r.isZero() or r.ge(ELEMENT_UPPER_BOUND)) {
        return SignError.InvalidK;
    }

    const k_inv = k.modInverse(EC_ORDER);
    const result = r.mul(private_key).mod(EC_ORDER);
    const s = result.add(message);

    return .{
        .r = private_key,
        .s = message,
        .v = k,
    };
}
