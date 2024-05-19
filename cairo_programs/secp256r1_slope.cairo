%builtins range_check

// Source: https://github.com/myBraavos/efficient-secp256r1/blob/main/src/secp256r1/ec.cairo

from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.field import (
    is_zero,
    unreduced_mul,
    unreduced_sqr,
    verify_zero,
)
from starkware.cairo.common.cairo_secp.ec import EcPoint


// Returns the slope of the line connecting the two given points.
// The slope is used to compute pt0 + pt1.
// Assumption: pt0.x != pt1.x (mod secp256k1_prime).
func compute_slope{range_check_ptr: felt}(point0: EcPoint, point1: EcPoint) -> (slope: BigInt3) {
    %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P %}
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        from starkware.python.math_utils import line_slope
        
        # Compute the slope.
        x0 = pack(ids.point0.x, PRIME)
        y0 = pack(ids.point0.y, PRIME)
        x1 = pack(ids.point1.x, PRIME)
        y1 = pack(ids.point1.y, PRIME)
        value = slope = line_slope(point1=(x0, y0), point2=(x1, y1), p=SECP_P)
    %}
    let (slope) = nondet_bigint3();

    return (slope=slope);
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

    assert slope = slope;
    return ();
}

func main{range_check_ptr: felt}(){
    test_compute_slope();

    return ();
}
