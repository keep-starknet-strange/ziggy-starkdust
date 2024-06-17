%builtins range_check

// Source: https://github.com/rdubois-crypto/efficient-secp256r1/blob/4b74807c5e91f1ed4cb00a1c973be05c63986e61/src/secp256r1/ec.cairo
from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.ec import EcPoint

// src.secp256r1.constants
// SECP_REM is defined by the equation:
//   secp256r1_prime = 2 ** 256 - SECP_REM.
const SECP_REM = 2 ** 224 - 2 ** 192 - 2 ** 96 + 1;

const BASE = 2 ** 86;

// A =  0xffffffff00000001000000000000000000000000fffffffffffffffffffffffc
const A0 = 0x3ffffffffffffffffffffc;
const A1 = 0x3ff;
const A2 = 0xffffffff0000000100000;

// Constants for unreduced_mul/sqr
const s2 = (-(2 ** 76)) - 2 ** 12;
const s1 = (-(2 ** 66)) + 4;
const s0 = 2 ** 56;

const r2 = 2 ** 54 - 2 ** 22;
const r1 = -(2 ** 12);
const r0 = 4;

// src.secp256r1.field
// Adapt from starkware.cairo.common.math's assert_250_bit
func assert_165_bit{range_check_ptr}(value) {
    const UPPER_BOUND = 2 ** 165;
    const SHIFT = 2 ** 128;
    const HIGH_BOUND = UPPER_BOUND / SHIFT;

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

    assert [range_check_ptr + 2] = HIGH_BOUND - 1 - high;

    assert value = high * SHIFT + low;

    let range_check_ptr = range_check_ptr + 3;
    return ();
}

// src.secp256r1.field
// Computes the multiplication of two big integers, given in BigInt3 representation, modulo the
// secp256r1 prime.
//
// Arguments:
//   x, y - the two BigInt3 to operate on.
//
// Returns:
//   x * y in an UnreducedBigInt3 representation (the returned limbs may be above 3 * BASE).
//
// This means that if unreduced_mul is called on the result of nondet_bigint3, or the difference
// between two such results, we have:
//   Soundness guarantee: the limbs are in the range ().
//   Completeness guarantee: the limbs are in the range ().
func unreduced_mul(a: BigInt3, b: BigInt3) -> (res_low: UnreducedBigInt3) {
    tempvar twice_d2 = a.d2 * b.d2;
    tempvar d1d2 = a.d2 * b.d1 + a.d1 * b.d2;
    return (
        UnreducedBigInt3(
            d0=a.d0 * b.d0 + s0 * twice_d2 + r0 * d1d2,
            d1=a.d1 * b.d0 + a.d0 * b.d1 + s1 * twice_d2 + r1 * d1d2,
            d2=a.d2 * b.d0 + a.d1 * b.d1 + a.d0 * b.d2 + s2 * twice_d2 + r2 * d1d2,
        ),
    );
}

// src.secp256r1.field
// Computes the square of a big integer, given in BigInt3 representation, modulo the
// secp256r1 prime.
//
// Has the same guarantees as in unreduced_mul(a, a).
func unreduced_sqr(a: BigInt3) -> (res_low: UnreducedBigInt3) {
    tempvar twice_d2 = a.d2 * a.d2;
    tempvar twice_d1d2 = a.d2 * a.d1 + a.d1 * a.d2;
    tempvar d1d0 = a.d1 * a.d0;
    return (
        UnreducedBigInt3(
            d0=a.d0 * a.d0 + s0 * twice_d2 + r0 * twice_d1d2,
            d1=d1d0 + d1d0 + s1 * twice_d2 + r1 * twice_d1d2,
            d2=a.d2 * a.d0 + a.d1 * a.d1 + a.d0 * a.d2 + s2 * twice_d2 + r2 * twice_d1d2,
        ),
    );
}

// src.secp256r1.field
// Verifies that the given unreduced value is equal to zero modulo the secp256r1 prime.
//
// Completeness assumption: val's limbs are in the range (-2**210.99, 2**210.99).
// Soundness assumption: val's limbs are in the range (-2**250, 2**250).
func verify_zero{range_check_ptr}(val: UnreducedBigInt3) {
    alloc_locals;
    local q;
    // local q_sign;
    let q_sign = 1;
    // original:
    // %{ from starkware.cairo.common.cairo_secp.secp_utils import SECP256R1_P as SECP_P %}
    // %{
    //     from starkware.cairo.common.cairo_secp.secp_utils import pack

    // q, r = divmod(pack(ids.val, PRIME), SECP_P)
    //     assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
    //     if q >= 0:
    //         ids.q = q % PRIME
    //         ids.q_sign = 1
    //     else:
    //         ids.q = (0-q) % PRIME
    //         ids.q_sign = -1 % PRIME
    // %}
    %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P %}
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack

        q, r = divmod(pack(ids.val, PRIME), SECP_P)
        assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
        ids.q = q % PRIME
    %}
    // assert_250_bit(q); // 256K steps
    // assert_le_felt(q, 2**165); // 275K steps
    assert_165_bit(q);
    assert q_sign * (val.d2 + val.d1 / BASE + val.d0 / BASE ** 2) = q * (
        (BASE / 4) - SECP_REM / BASE ** 2
    );
    // Multiply by BASE**2 both sides:
    //  (q_sign) * val = q * (BASE**3 / 4 - SECP_REM)
    //            = q * (2**256 - SECP_REM) = q * secp256r1_prime = 0 mod secp256r1_prime
    return ();
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
    // Note that y cannot be zero: assume that it is, then point = -point, so 2 * point = 0, which
    // contradicts the fact that the size of the curve is odd.
    // originals:
    // %{ from starkware.cairo.common.cairo_secp.secp_utils import SECP256R1_P as SECP_P %}
    // %{ from starkware.cairo.common.cairo_secp.secp_utils import SECP256R1_ALPHA as ALPHA %}
    %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P %}
    %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_ALPHA as ALPHA %}
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        from starkware.python.math_utils import ec_double_slope

        # Compute the slope.
        x = pack(ids.point.x, PRIME)
        y = pack(ids.point.y, PRIME)
        value = slope = ec_double_slope(point=(x, y), alpha=ALPHA, p=SECP_P)
    %}
    let (slope: BigInt3) = nondet_bigint3();

    let (x_sqr: UnreducedBigInt3) = unreduced_sqr(point.x);
    let (slope_y: UnreducedBigInt3) = unreduced_mul(slope, point.y);
    verify_zero(
        UnreducedBigInt3(
            d0=3 * x_sqr.d0 + A0 - 2 * slope_y.d0,
            d1=3 * x_sqr.d1 + A1 - 2 * slope_y.d1,
            d2=3 * x_sqr.d2 + A2 - 2 * slope_y.d2,
        ),
    );

    return (slope=slope);
}

func test_doubling_slope{range_check_ptr}() {
    let point = EcPoint(BigInt3(614323, 5456867, 101208), BigInt3(773712524, 77371252, 5298795));

    let (slope) = compute_doubling_slope(point);

    assert slope = BigInt3(
        64081873649130491683833713, 34843994309543177837008178, 16548672716077616016846383
    );

    let point = EcPoint(
        BigInt3(51215, 36848548548458, 634734734), BigInt3(26362, 263724839599, 901297012)
    );

    let (slope) = compute_doubling_slope(point);

    assert slope = BigInt3(
        71848883893335852660776740, 75644451964360469099209675, 547087410329256463669633
    );

    return ();
}

func main{range_check_ptr}() {
    test_doubling_slope();
    return ();
}
