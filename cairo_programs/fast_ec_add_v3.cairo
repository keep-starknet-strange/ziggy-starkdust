%builtins range_check
from starkware.cairo.common.cairo_secp.bigint import BigInt3, nondet_bigint3, UnreducedBigInt3
from starkware.cairo.common.cairo_secp.field import (
    is_zero,
    unreduced_sqr,
    unreduced_mul
)
from starkware.cairo.common.cairo_secp.ec import compute_slope, EcPoint, verify_zero
// Computes the addition of two given points.
//
// Arguments:
//   pt0, pt1 - the points to operate on.
//
// Returns:
//   res - the sum of the two points (pt0 + pt1).
//
// Assumption: pt0.x != pt1.x (however, pt0 = pt1 = 0 is allowed).
// Note that this means that the function cannot be used if pt0 = pt1 != 0
// (use ec_double() in this case) or pt0 = -pt1 != 0 (the result is 0 in this case).
func fast_ec_add{range_check_ptr}(pt0: EcPoint, pt1: EcPoint) -> (res: EcPoint) {
    // Check whether pt0 is the zero point.
    if (pt0.x.d0 == 0) {
        if (pt0.x.d1 == 0) {
            if (pt0.x.d2 == 0) {
                return (res=pt1);
            }
        }
    }

    // Check whether pt1 is the zero point.
    if (pt1.x.d0 == 0) {
        if (pt1.x.d1 == 0) {
            if (pt1.x.d2 == 0) {
                return (res=pt0);
            }
        }
    }

    let (slope: BigInt3) = compute_slope(pt0, pt1);
    let (slope_sqr: UnreducedBigInt3) = unreduced_sqr(slope);

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        slope = pack(ids.slope, PRIME)
        x0 = pack(ids.pt0.x, PRIME)
        x1 = pack(ids.pt1.x, PRIME)
        y0 = pack(ids.pt0.y, PRIME)

        value = new_x = (pow(slope, 2, SECP_P) - x0 - x1) % SECP_P
    %}
    let (new_x: BigInt3) = nondet_bigint3();

    %{ value = new_y = (slope * (x0 - new_x) - y0) % SECP_P %}
    let (new_y: BigInt3) = nondet_bigint3();

    verify_zero(
        UnreducedBigInt3(
            d0=slope_sqr.d0 - new_x.d0 - pt0.x.d0 - pt1.x.d0,
            d1=slope_sqr.d1 - new_x.d1 - pt0.x.d1 - pt1.x.d1,
            d2=slope_sqr.d2 - new_x.d2 - pt0.x.d2 - pt1.x.d2,
        ),
    );

    let (x_diff_slope: UnreducedBigInt3) = unreduced_mul(
        BigInt3(d0=pt0.x.d0 - new_x.d0, d1=pt0.x.d1 - new_x.d1, d2=pt0.x.d2 - new_x.d2),
        slope,
    );

    verify_zero(
        UnreducedBigInt3(
            d0=x_diff_slope.d0 - pt0.y.d0 - new_y.d0,
            d1=x_diff_slope.d1 - pt0.y.d1 - new_y.d1,
            d2=x_diff_slope.d2 - pt0.y.d2 - new_y.d2,
        ),
    );

    return (res=EcPoint(new_x, new_y));
}

func main{range_check_ptr}() {
    let x_0 = BigInt3(1,2,3);
    let y_0 = BigInt3(4,5,6);
    let p_0 = EcPoint(x_0, y_0);

    let x_1 = BigInt3(7,8,9);
    let y_1 = BigInt3(10,11,12);
    let p_1 = EcPoint(x_1, y_1);

    let (r) = fast_ec_add(p_0, p_1);

    assert r.x.d0 = 77371252455336262886226984;
    assert r.x.d1 = 77371252455336267181195253;
    assert r.x.d2 = 19342813113834066795298803;

    assert r.y.d0 = 4;
    assert r.y.d1 = 7;
    assert r.y.d2 = 9;

    return ();
}
