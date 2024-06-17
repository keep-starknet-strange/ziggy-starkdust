%builtins range_check

// Source: https://github.com/NilFoundation/cairo-ed25519/blob/fee64a1a60b2e07b3b5c20df57f31d7ffcb29ac9/ed25519_ec.cairo

from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.field import (
    is_zero,
    unreduced_mul,
    unreduced_sqr,
    verify_zero,
)

// Represents a point on the elliptic curve.
// The zero point is represented using pt.x=0, as there is no point on the curve with this x value.
struct EcPoint {
    x: BigInt3,
    y: BigInt3,
}

// Returns the slope of the elliptic curve at the given point.
// The slope is used to compute pt + pt.
// Assumption: pt != 0.
func compute_doubling_slope{range_check_ptr}(pt: EcPoint) -> (slope: BigInt3) {
    // Note that y cannot be zero: assume that it is, then pt = -pt, so 2 * pt = 0, which
    // contradicts the fact that the size of the curve is odd.
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack
        from starkware.python.math_utils import div_mod

        # Compute the slope.
        x = pack(ids.pt.x, PRIME)
        y = pack(ids.pt.y, PRIME)
        value = slope = div_mod(3 * x ** 2, 2 * y, SECP_P)
    %}
    let (slope: BigInt3) = nondet_bigint3();

    let (x_sqr: UnreducedBigInt3) = unreduced_sqr(pt.x);
    let (slope_y: UnreducedBigInt3) = unreduced_mul(slope, pt.y);

    verify_zero(
        UnreducedBigInt3(
            d0=3 * x_sqr.d0 - 2 * slope_y.d0,
            d1=3 * x_sqr.d1 - 2 * slope_y.d1,
            d2=3 * x_sqr.d2 - 2 * slope_y.d2,
        ),
    );

    return (slope=slope);
}

// Returns the slope of the line connecting the two given points.
// The slope is used to compute pt0 + pt1.
// Assumption: pt0.x != pt1.x (mod secp256k1_prime).
func compute_slope{range_check_ptr: felt}(pt0: EcPoint, pt1: EcPoint) -> (slope: BigInt3) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack
        from starkware.python.math_utils import div_mod

        # Compute the slope.
        x0 = pack(ids.pt0.x, PRIME)
        y0 = pack(ids.pt0.y, PRIME)
        x1 = pack(ids.pt1.x, PRIME)
        y1 = pack(ids.pt1.y, PRIME)
        value = slope = div_mod(y0 - y1, x0 - x1, SECP_P)
    %}
    let (slope) = nondet_bigint3();

    let x_diff = BigInt3(d0=pt0.x.d0 - pt1.x.d0, d1=pt0.x.d1 - pt1.x.d1, d2=pt0.x.d2 - pt1.x.d2);
    let (x_diff_slope: UnreducedBigInt3) = unreduced_mul(x_diff, slope);

    verify_zero(
        UnreducedBigInt3(
            d0=x_diff_slope.d0 - pt0.y.d0 + pt1.y.d0,
            d1=x_diff_slope.d1 - pt0.y.d1 + pt1.y.d1,
            d2=x_diff_slope.d2 - pt0.y.d2 + pt1.y.d2,
        ),
    );

    return (slope=slope);
}

func test_compute_double_slope{range_check_ptr: felt}() {
    let x = BigInt3(d0=33, d1=24, d2=12412);
    let y = BigInt3(d0=3232, d1=122, d2=31415);

    let pt = EcPoint(x=x, y=y);

    // Compute slope
    let (slope) = compute_doubling_slope(pt);

    assert slope = BigInt3(
        d0=56007611085086895200895667, d1=15076814030975805918069142, d2=6556143173243739984479201
    );

    return ();
}

func test_compute_slope{range_check_ptr: felt}() {
    let x0 = BigInt3(d0=1, d1=5, d2=10);
    let y0 = BigInt3(d0=2, d1=4, d2=20);

    let pt0 = EcPoint(x=x0, y=y0);

    let x1 = BigInt3(d0=3, d1=3, d2=3);
    let y1 = BigInt3(d0=3, d1=5, d2=22);

    let pt1 = EcPoint(x=x1, y=y1);

    // Compute slope
    let (slope) = compute_slope(pt0, pt1);

    assert slope = BigInt3(
        d0=39919528597790922692721903, d1=31451568879578276714332055, d2=6756007504256943629292535
    );

    return ();
}

func main{range_check_ptr: felt}() {
    test_compute_double_slope();
    test_compute_slope();

    return ();
}
