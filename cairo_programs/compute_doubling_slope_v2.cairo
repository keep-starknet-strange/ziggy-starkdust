
from starkware.cairo.common.cairo_secp.bigint import (
    BigInt3,
    UnreducedBigInt3,
    nondet_bigint3,
)

from cairo_programs.compute_slope_v2 import verify_zero

const BASE = 2 ** 86;
const SECP_REM = 19;

struct EcPoint {
    x: BigInt3,
    y: BigInt3,
}

func unreduced_mul(a: BigInt3, b: BigInt3) -> (res_low: UnreducedBigInt3) {
    // The result of the product is:
    //   sum_{i, j} a.d_i * b.d_j * BASE**(i + j)
    // Since we are computing it mod secp256k1_prime, we replace the term
    //   a.d_i * b.d_j * BASE**(i + j)
    // where i + j >= 3 with
    //   a.d_i * b.d_j * BASE**(i + j - 3) * 4 * SECP_REM
    // since BASE ** 3 = 4 * SECP_REM (mod secp256k1_prime).
    return (
        UnreducedBigInt3(
        d0=a.d0 * b.d0 + (a.d1 * b.d2 + a.d2 * b.d1) * (8 * SECP_REM),
        d1=a.d0 * b.d1 + a.d1 * b.d0 + (a.d2 * b.d2) * (8 * SECP_REM),
        d2=a.d0 * b.d2 + a.d1 * b.d1 + a.d2 * b.d0),
    );
}

// Computes the square of a big integer, given in BigInt3 representation, modulo the
// secp256k1 prime.
//
// Has the same guarantees as in unreduced_mul(a, a).
func unreduced_sqr(a: BigInt3) -> (res_low: UnreducedBigInt3) {
    tempvar twice_d0 = a.d0 * 2;
    return (
        UnreducedBigInt3(
        d0=a.d0 * a.d0 + (a.d1 * a.d2) * (2 * 8 * SECP_REM),
        d1=twice_d0 * a.d1 + (a.d2 * a.d2) * (8 * SECP_REM),
        d2=twice_d0 * a.d2 + a.d1 * a.d1),
    );
}

    
// Computes the slope of the elliptic curve at a given point.
// The slope is used to compute point + point.
//
// Arguments:
//   point - the point to operate on.
//
// Returns:
//   slope - the slope of the curve at point, in BigInt3 representation.
//
// Assumption: point != 0.

func compute_doubling_slope{range_check_ptr}(point: EcPoint) -> (slope: BigInt3) {
    alloc_locals;
    // Note that y cannot be zero: assume that it is, then point = -point, so 2 * point = 0, which
    // contradicts the fact that the size of the curve is odd.
    %{
        from starkware.python.math_utils import ec_double_slope
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P = 2**255-19

        # Compute the slope.
        x = pack(ids.point.x, PRIME)
        y = pack(ids.point.y, PRIME)
        value = slope = ec_double_slope(point=(x, y), alpha=42204101795669822316448953119945047945709099015225996174933988943478124189485, p=SECP_P)
    %}
    let (slope: BigInt3) = nondet_bigint3();
    // let alpha = Uint256(
    //     143186476941636880901214103594843510573, 124026708105846590725274683684370988502
    // );
    let (x_sqr: UnreducedBigInt3) = unreduced_sqr(point.x);
    let (slope_y: UnreducedBigInt3) = unreduced_mul(slope, point.y);
    let to_assert = UnreducedBigInt3(
        d0=3 * x_sqr.d0 - 2 * slope_y.d0 + 44933163489768861888943917,
        d1=3 * x_sqr.d1 - 2 * slope_y.d1 + 5088459194227531129123890,
        d2=3 * x_sqr.d2 - 2 * slope_y.d2 + 7050102118787810395887998,
    );
    // let to_assert256 = bigint_to_uint256(to_assert);
    // %{ print_u_256_info(ids.to_assert256, 'to_assert') %}

    verify_zero(to_assert);

    return (slope=slope);
}


func main{range_check_ptr}() {
    let point_1 = EcPoint(BigInt3(512, 2412, 133), BigInt3(64, 0, 6546));

    let (slope) = compute_doubling_slope(point_1);
    assert slope = BigInt3(50745345459537348646984154, 66221251087242098185359002 ,8063180118678125382645462);
    return ();
    }
