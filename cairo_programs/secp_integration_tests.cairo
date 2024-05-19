%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import (
    BigInt3,
    bigint_mul,
    nondet_bigint3,
    bigint_to_uint256,
    uint256_to_bigint,
)
from starkware.cairo.common.cairo_secp.signature import (
    get_generator_point,
    validate_signature_entry,
    div_mod_n,
    recover_public_key,
    get_point_from_x,
    verify_zero,
    reduce,
    unreduced_mul,
)
from starkware.cairo.common.cairo_secp.field import is_zero
from starkware.cairo.common.cairo_secp.constants import N0, N1, N2, BASE, SECP_REM
from starkware.cairo.common.cairo_secp.ec import (
    EcPoint,
    ec_add,
    ec_mul,
    ec_negate,
    ec_double,
    fast_ec_add,
    compute_doubling_slope,
    compute_slope,
    ec_mul_inner,
)
from starkware.cairo.common.math import assert_nn_le, assert_not_zero
from starkware.cairo.common.uint256 import (
    Uint256,
    split_64,
    uint256_signed_nn,
    uint256_cond_neg,
    uint256_neg,
    uint256_add,
)

// Verifies a Secp256k1 ECDSA signature.
// Soundness assumptions:
// * public_key_pt is on the curve.
// * All the limbs of public_key_pt.x, public_key_pt.y, msg_hash are in the range [0, 3 * BASE).
func verify_ecdsa{range_check_ptr}(
    public_key_pt: EcPoint, msg_hash: BigInt3, r: BigInt3, s: BigInt3
) -> (res: EcPoint) {
    alloc_locals;

    validate_signature_entry(r);
    validate_signature_entry(s);

    let gen_pt = EcPoint(
        BigInt3(0xe28d959f2815b16f81798, 0xa573a1c2c1c0a6ff36cb7, 0x79be667ef9dcbbac55a06),
        BigInt3(0x554199c47d08ffb10d4b8, 0x2ff0384422a3f45ed1229a, 0x483ada7726a3c4655da4f),
    );

    // Compute u1 and u2.
    let (u1: BigInt3) = div_mod_n(msg_hash, s);
    let (u2: BigInt3) = div_mod_n(r, s);

    let (gen_u1) = ec_mul(gen_pt, u1);
    let (pub_u2) = ec_mul(public_key_pt, u2);
    let (res) = ec_add(gen_u1, pub_u2);

    // The following assert also implies that res is not the zero point.
    assert res.x = r;
    return (res,);
}

func test_operations{range_check_ptr}(point: EcPoint) {
    alloc_locals;
    let (negated) = ec_negate(point);
    let (double_negated) = ec_double(negated);
    let (expect_negated) = fast_ec_add(double_negated, point);

    assert negated = expect_negated;

    let (doubling_slope) = compute_doubling_slope(expect_negated);

    let (slope) = compute_slope(expect_negated, double_negated);
    let (slope_uint) = bigint_to_uint256(slope);
    let (neg_slope) = uint256_neg(slope_uint);
    let (zero_uint, _) = uint256_add(slope_uint, neg_slope);
    let (zero) = uint256_to_bigint(zero_uint);

    let (is_z) = is_zero(zero);
    assert is_z = 1;

    let (pow2, scaled) = ec_mul_inner(point, 0, 0);
    assert scaled = EcPoint(BigInt3(0, 0, 0), BigInt3(0, 0, 0));
    assert pow2 = point;

    return ();
}

func get_valid_point{range_check_ptr}(noise: felt) -> (curve_point: EcPoint) {
    let (valid_point) = get_generator_point();
    let scalar = BigInt3(noise, noise * 2, noise + 5);
    let (point) = ec_mul(valid_point, scalar);
    let (curve_point) = get_point_from_x(point.x, noise);
    return (curve_point,);
}

func run_tests{range_check_ptr}(index: felt, stop: felt) {
    alloc_locals;
    if (index == stop) {
        return ();
    }

    let r = BigInt3(4, 5, 6);
    let (s) = get_valid_point(index);
    let msg_hash = BigInt3(1, 2, 3);
    let (public_key_pt) = recover_public_key(msg_hash=msg_hash, r=r, s=s.x, v=0);

    let (point) = verify_ecdsa(public_key_pt=public_key_pt, msg_hash=msg_hash, r=r, s=s.x);

    test_operations(point);
    return run_tests(index + 1, stop);
}

func main{range_check_ptr}() {
    // These values have triggered a bug in the past
    run_tests(4, 5);
    return ();
}
