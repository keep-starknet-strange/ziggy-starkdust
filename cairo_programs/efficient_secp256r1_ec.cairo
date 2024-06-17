%builtins range_check

// Source: https://github.com/myBraavos/efficient-secp256r1/blob/73cca4d53730cb8b2dcf34e36c7b8f34b96b3230/src/secp256r1/ec.cairo#L127

from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.ec import EcPoint, compute_doubling_slope
from starkware.cairo.common.cairo_secp.field import (
    is_zero,
    unreduced_mul,
    unreduced_sqr,
    verify_zero,
)

// Computes the addition of a given point to itself.
//
// Arguments:
//   point - the point to operate on.
//
// Returns:
//   res - a point representing point + point.
func ec_double{range_check_ptr}(point: EcPoint) -> (res: EcPoint) {
    // The zero point.
    if (point.x.d0 == 0) {
        if (point.x.d1 == 0) {
            if (point.x.d2 == 0) {
                return (res=point);
            }
        }
    }

    let (slope: BigInt3) = compute_doubling_slope(point);
    let (slope_sqr: UnreducedBigInt3) = unreduced_sqr(slope);

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack

        slope = pack(ids.slope, PRIME)
        x = pack(ids.point.x, PRIME)
        y = pack(ids.point.y, PRIME)

        value = new_x = (pow(slope, 2, SECP_P) - 2 * x) % SECP_P
    %}
    let (new_x: BigInt3) = nondet_bigint3();

    %{ value = new_y = (slope * (x - new_x) - y) % SECP_P %}
    let (new_y: BigInt3) = nondet_bigint3();
    verify_zero(
        UnreducedBigInt3(
            d0=slope_sqr.d0 - new_x.d0 - 2 * point.x.d0,
            d1=slope_sqr.d1 - new_x.d1 - 2 * point.x.d1,
            d2=slope_sqr.d2 - new_x.d2 - 2 * point.x.d2,
        ),
    );

    let (x_diff_slope: UnreducedBigInt3) = unreduced_mul(
        BigInt3(d0=point.x.d0 - new_x.d0, d1=point.x.d1 - new_x.d1, d2=point.x.d2 - new_x.d2), slope
    );
    verify_zero(
        UnreducedBigInt3(
            d0=x_diff_slope.d0 - point.y.d0 - new_y.d0,
            d1=x_diff_slope.d1 - point.y.d1 - new_y.d1,
            d2=x_diff_slope.d2 - point.y.d2 - new_y.d2,
        ),
    );

    return (res=EcPoint(new_x, new_y));
}

func main{range_check_ptr: felt}() {
    let x = BigInt3(235, 522, 111);
    let y = BigInt3(1323, 15124, 796759);

    let point = EcPoint(x, y);

    let (res) = ec_double(point);

    assert res = EcPoint(
        BigInt3(64960503569511978748964127, 74077005698377320581054215, 17246103581201827820088765),
        BigInt3(13476289913106792137931934, 29193128211607101710049068, 18079689234850912663169436),
    );

    return ();
}
