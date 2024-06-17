
from starkware.cairo.common.cairo_secp.bigint import BigInt3, nondet_bigint3, UnreducedBigInt3
from starkware.cairo.common.cairo_secp.field import (
    is_zero,
    unreduced_sqr,
)
from cairo_programs.compute_slope_v2 import compute_slope, EcPoint, verify_zero, unreduced_mul
// Computes the addition of two given points.
//
// Arguments:
//   point0, point1 - the points to operate on.
//
// Returns:
//   res - the sum of the two points (point0 + point1).
//
// Assumption: point0.x != point1.x (however, point0 = point1 = 0 is allowed).
// Note that this means that the function cannot be used if point0 = point1 != 0
// (use ec_double() in this case) or point0 = -point1 != 0 (the result is 0 in this case).
func fast_ec_add{range_check_ptr}(point0: EcPoint, point1: EcPoint) -> (res: EcPoint) {
    // Check whether point0 is the zero point.
    if (point0.x.d0 == 0) {
        if (point0.x.d1 == 0) {
            if (point0.x.d2 == 0) {
                return (res=point1);
            }
        }
    }

    // Check whether point1 is the zero point.
    if (point1.x.d0 == 0) {
        if (point1.x.d1 == 0) {
            if (point1.x.d2 == 0) {
                return (res=point0);
            }
        }
    }

    let (slope: BigInt3) = compute_slope(point0, point1);
    let (slope_sqr: UnreducedBigInt3) = unreduced_sqr(slope);

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P = 2**255-19

        slope = pack(ids.slope, PRIME)
        x0 = pack(ids.point0.x, PRIME)
        x1 = pack(ids.point1.x, PRIME)
        y0 = pack(ids.point0.y, PRIME)

        value = new_x = (pow(slope, 2, SECP_P) - x0 - x1) % SECP_P
    %}
    let (new_x: BigInt3) = nondet_bigint3();

    %{ value = new_y = (slope * (x0 - new_x) - y0) % SECP_P %}
    let (new_y: BigInt3) = nondet_bigint3();

    verify_zero(
        UnreducedBigInt3(
            d0=slope_sqr.d0 - new_x.d0 - point0.x.d0 - point1.x.d0,
            d1=slope_sqr.d1 - new_x.d1 - point0.x.d1 - point1.x.d1,
            d2=slope_sqr.d2 - new_x.d2 - point0.x.d2 - point1.x.d2,
        ),
    );

    let (x_diff_slope: UnreducedBigInt3) = unreduced_mul(
        BigInt3(d0=point0.x.d0 - new_x.d0, d1=point0.x.d1 - new_x.d1, d2=point0.x.d2 - new_x.d2),
        slope,
    );

    verify_zero(
        UnreducedBigInt3(
            d0=x_diff_slope.d0 - point0.y.d0 - new_y.d0,
            d1=x_diff_slope.d1 - point0.y.d1 - new_y.d1,
            d2=x_diff_slope.d2 - point0.y.d2 - new_y.d2,
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

    assert r.x.d0 = 77371252455336267181195238;
    assert r.x.d1 = 77371252455336267181195253;
    assert r.x.d2 = 9671406556917033397649395;

    assert r.y.d0 = 4;
    assert r.y.d1 = 7;
    assert r.y.d2 = 9;

    return ();
}
