const std = @import("std");
const Felt252 = @import("../fields/starknet.zig").Felt252;
const ProjectivePoint = @import("../crypto/curve/ec_point.zig").ProjectivePoint;
const AffinePoint = @import("../crypto/curve/ec_point.zig").AffinePoint;
const VerifyError = @import("../../vm/error.zig").VerifyError;

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

/// Computes the public key given a Stark private key.
///
/// ### Arguments
///
/// * `private_key`: The private key
pub fn getPublicKey(private_key: Felt252) Felt252 {
    return mulByBits(GENERATOR, private_key).x;
}

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

    const k_inv = try k.modInverse(EC_ORDER);

    var s = r.mulModFloor(private_key, EC_ORDER);
    s = s.add(message);
    s = s.mulModFloor(k_inv, EC_ORDER);

    if (s.equal(Felt252.zero()) or s.ge(ELEMENT_UPPER_BOUND)) {
        return SignError.InvalidK;
    }

    const v = full_r.y.bitAnd(Felt252.one());

    return .{
        .r = r,
        .s = s,
        .v = v,
    };
}

pub fn verify(
    public_key: Felt252,
    message: Felt252,
    r: Felt252,
    s: Felt252,
) !bool {
    if (message.ge(ELEMENT_UPPER_BOUND)) {
        return VerifyError.InvalidMessageHash;
    }

    if (r.equal(Felt252.zero()) or r.ge(ELEMENT_UPPER_BOUND)) {
        return VerifyError.InvalidR;
    }

    if (s.equal(Felt252.zero()) or s.ge(ELEMENT_UPPER_BOUND)) {
        return VerifyError.InvalidS;
    }

    const full_public_key = try AffinePoint.fromX(public_key);

    const w = try s.modInverse(EC_ORDER);
    if (w.equal(Felt252.zero()) or w.ge(ELEMENT_UPPER_BOUND)) {
        return VerifyError.InvalidS;
    }

    const zw = message.mulModFloor(w, EC_ORDER);
    const zw_g = mulByBits(GENERATOR, zw);

    const rw = r.mulModFloor(w, EC_ORDER);
    const rw_q = mulByBits(full_public_key, rw);

    return (zw_g.add(rw_q).x.equal(r) or zw_g.sub(rw_q).x.equal(r));
}

test "ECDSA: verify signature" {
    const private_key = Felt252.fromInt(
        u256,
        0x0000000000000000000000000000000000000000000000000000000000000001,
    );

    const message = Felt252.fromInt(
        u256,
        0x0000000000000000000000000000000000000000000000000000000000000002,
    );

    const k = Felt252.fromInt(
        u256,
        0x0000000000000000000000000000000000000000000000000000000000000003,
    );

    const signature = try sign(private_key, message, k);
    const public_key = getPublicKey(private_key);

    try std.testing.expect(try verify(public_key, message, signature.r, signature.s));
}
