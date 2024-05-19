%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.ec import compute_doubling_slope, EcPoint
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
func ec_double{range_check_ptr}(pt: EcPoint) -> (res: EcPoint) {
    // The zero point.
    if (pt.x.d0 == 0) {
        if (pt.x.d1 == 0) {
            if (pt.x.d2 == 0) {
                return (res=pt);
            }
        }
    }

    let (slope: BigInt3) = compute_doubling_slope(pt);
    let (slope_sqr: UnreducedBigInt3) = unreduced_sqr(slope);

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        slope = pack(ids.slope, PRIME)
        x = pack(ids.pt.x, PRIME)
        y = pack(ids.pt.y, PRIME)

        value = new_x = (pow(slope, 2, SECP_P) - 2 * x) % SECP_P
    %}
    let (new_x: BigInt3) = nondet_bigint3();

    %{ value = new_y = (slope * (x - new_x) - y) % SECP_P %}
    let (new_y: BigInt3) = nondet_bigint3();

    verify_zero(
        UnreducedBigInt3(
            d0=slope_sqr.d0 - new_x.d0 - 2 * pt.x.d0,
            d1=slope_sqr.d1 - new_x.d1 - 2 * pt.x.d1,
            d2=slope_sqr.d2 - new_x.d2 - 2 * pt.x.d2,
        ),
    );

    let (x_diff_slope: UnreducedBigInt3) = unreduced_mul(
        BigInt3(d0=pt.x.d0 - new_x.d0, d1=pt.x.d1 - new_x.d1, d2=pt.x.d2 - new_x.d2), slope
    );

    verify_zero(
        UnreducedBigInt3(
            d0=x_diff_slope.d0 - pt.y.d0 - new_y.d0,
            d1=x_diff_slope.d1 - pt.y.d1 - new_y.d1,
            d2=x_diff_slope.d2 - pt.y.d2 - new_y.d2,
        ),
    );

    return (res=EcPoint(new_x, new_y));
}

func main{range_check_ptr}() {
    let x = BigInt3(7,8,9);
    let y = BigInt3(19,29,30);
    let p = EcPoint(x, y);
    let (r) = ec_double(p);

    assert r.x.d0 = 51257743837507631919880152;
    assert r.x.d1 = 64460046105241149334147278;
    assert r.x.d2 = 12582041431145599112140654;

    assert r.y.d0 = 19321524266852839048503535;
    assert r.y.d1 = 35591956483215965716767025;
    assert r.y.d2 = 12630971731313051616919773;

    return();
}
