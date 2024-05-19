%builtins range_check

// Source: https://github.com/myBraavos/efficient-secp256r1/blob/main/src/secp256r1/ec.cairo#L188

from starkware.cairo.common.cairo_secp.bigint import BigInt3, nondet_bigint3, BASE, bigint_mul, UnreducedBigInt3
from starkware.cairo.common.cairo_secp.ec import EcPoint

// N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
const N0 = 0x179e84f3b9cac2fc632551;
const N1 = 0x3ffffffffffef39beab69c;
const N2 = 0xffffffff00000000fffff;

// Constants for unreduced_mul/sqr
const s2 = -2**76 - 2**12;
const s1 = -2**66 + 4;
const s0 = 2**56;

const r2 = 2**54 - 2**22;
const r1 = -2**12;
const r0 = 4;

// SECP_REM =  2**224 - 2**192 - 2**96 + 1
const SECP_REM0 = 1;
const SECP_REM1 = -2**10;
const SECP_REM2 = 0xffffffff00000;

func assert_165_bit{range_check_ptr}(value) {
    const UPPER_BOUND = 2 ** 165;
    const SHIFT = 2 ** 128;
    const HIGH_BOUND = SHIFT - UPPER_BOUND / SHIFT;

    let low = [range_check_ptr];
    let high = [range_check_ptr + 1];

    %{
        from starkware.cairo.common.math_utils import as_int

        # Correctness check.
        value = as_int(ids.value, PRIME) % PRIME
        assert value < ids.UPPER_BOUND, f'{value} is outside of the range [0, 2**250).'

        # Calculation for the assertion.
        ids.high, ids.low = divmod(ids.value, ids.SHIFT)
    %}

    assert [range_check_ptr + 2] = high + HIGH_BOUND;

    assert value = high * SHIFT + low;

    let range_check_ptr = range_check_ptr + 3;
    return ();
}

func unreduced_mul(a: BigInt3, b: BigInt3) -> (res_low: UnreducedBigInt3) {
    tempvar twice_d2 = a.d2*b.d2;
    tempvar d1d2 = a.d2*b.d1 + a.d1*b.d2;
    return (
        UnreducedBigInt3(
            d0=a.d0*b.d0 + s0*twice_d2 + r0*d1d2,
            d1=a.d1*b.d0 + a.d0*b.d1 + s1*twice_d2 + r1*d1d2,
            d2=a.d2*b.d0 + a.d1*b.d1 + a.d0*b.d2 + s2*twice_d2 + r2*d1d2,
        ),
    );
}

func unreduced_sqr(a: BigInt3) -> (res_low: UnreducedBigInt3) {
    tempvar twice_d2 = a.d2*a.d2;
    tempvar twice_d1d2 = a.d2*a.d1 + a.d1*a.d2;
    tempvar d1d0 = a.d1*a.d0;
    return (
        UnreducedBigInt3(
            d0=a.d0*a.d0 + s0*twice_d2 + r0*twice_d1d2,
            d1=d1d0 + d1d0 + s1*twice_d2 + r1*twice_d1d2,
            d2=a.d2*a.d0 + a.d1*a.d1 + a.d0*a.d2 + s2*twice_d2 + r2*twice_d1d2,
        ),
    );
}

func verify_zero{range_check_ptr}(val: UnreducedBigInt3) {
    alloc_locals;
    local q;
    %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P %}
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack

        q, r = divmod(pack(ids.val, PRIME), SECP_P)
        assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
        ids.q = q % PRIME
    %}

    assert_165_bit(q + 2**164);
    // q in [-2**164, 2**164)

    tempvar r1 = (val.d0 + q * SECP_REM0) / BASE;
    assert_165_bit(r1 + 2**164);
    // r1 in [-2**164, 2**164) also meaning
    // numerator divides BASE which is the case when val divides secp256r1
    // so r1 * BASE = val.d0 + q*SECP_REM0 in the integers

    tempvar r2 = (val.d1 + q * SECP_REM1 + r1) / BASE;
    assert_165_bit(r2 + 2**164);
    // r2 in [-2**164, 2**164) following the same reasoning
    // so r2 * BASE = val.d1 + q*SECP_REM1 + r1 in the integers
    // so r2 * BASE ** 2 = val.d1 * BASE + q*SECP_REM1 * BASE + r1 * BASE

    assert val.d2 + q * SECP_REM2 = q * (BASE / 4) - r2;
    // both lhs and rhs are in (-2**250, 2**250) so assertion valid in the integers
    // multiply both sides by BASE**2
    // val.d2*BASE**2 + q * SECP_REM2*BASE**2
    //     = q * (2**256) - val.d1 * BASE + q*SECP_REM1 * BASE + val.d0 + q*SECP_REM0
    //  collect val on one side and all the rest on the other =>
    //  val = q*(2**256 - SECP_REM) = q * secp256r1 = 0 mod secp256r1

    return ();
}

func compute_slope{range_check_ptr}(point0: EcPoint, point1: EcPoint) -> (slope: BigInt3) {
    %{  from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P %}
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

    let x_diff = BigInt3(
        d0=point0.x.d0 - point1.x.d0, d1=point0.x.d1 - point1.x.d1, d2=point0.x.d2 - point1.x.d2
    );
    let (x_diff_slope: UnreducedBigInt3) = unreduced_mul(x_diff, slope);
    verify_zero(
        UnreducedBigInt3(
            d0=x_diff_slope.d0 - point0.y.d0 + point1.y.d0,
            d1=x_diff_slope.d1 - point0.y.d1 + point1.y.d1,
            d2=x_diff_slope.d2 - point0.y.d2 + point1.y.d2,
        ),
    );

    return (slope=slope);
}

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
    %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P %}
    // Hint #21
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack

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

func main{range_check_ptr}(){
    let x = BigInt3(1, 5, 10);
    let y = BigInt3(2, 4, 20);

    let point_a = EcPoint(x, y);
    let point_e = EcPoint(
        BigInt3(55117564152931927789817182, 33048130247267262167865975, 14533608608654363688616034),
        BigInt3(54056253314096377704781816, 68158355584365770862343034, 3052322168655618600739346),
    );

    // fast_ec_add
    let (point_f) = fast_ec_add(point_a, point_e);
    assert point_f = EcPoint(
        BigInt3(49699015624329293412442365, 46510866771824701261167999, 1989434117861440887085793),
        BigInt3(214124551187530669800637, 1052132420873960207582277, 4516480956028272815500807),
    );

    return ();
}
