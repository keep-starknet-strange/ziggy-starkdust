%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import (
    BigInt3,
    UnreducedBigInt3,
    nondet_bigint3,
    bigint_to_uint256,
    uint256_to_bigint,
)

struct EcPoint {
    x: BigInt3,
    y: BigInt3,
}

const BASE = 2 ** 86;
const SECP_REM = 19;

func compute_slope{range_check_ptr}(point0: EcPoint, point1: EcPoint) -> (slope: BigInt3) {
    alloc_locals;
    %{
        from starkware.python.math_utils import line_slope
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P = 2**255-19
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
        d2=x_diff_slope.d2 - point0.y.d2 + point1.y.d2),
    );

    return (slope=slope);
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

func verify_zero{range_check_ptr}(val: UnreducedBigInt3) {
    let q = [ap];
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P = 2**255-19
        to_assert = pack(ids.val, PRIME)
        q, r = divmod(pack(ids.val, PRIME), SECP_P)
        assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
        ids.q = q % PRIME
    %}
    let q_biased = [ap + 1];
    q_biased = q + 2 ** 127, ap++;
    [range_check_ptr] = q_biased, ap++;
    // This implies that q is in the range [-2**127, 2**127).

    tempvar r1 = (val.d0 + q * SECP_REM) / BASE;
    assert [range_check_ptr + 1] = r1 + 2 ** 127;
    // This implies that r1 is in the range [-2**127, 2**127).
    // Therefore, r1 * BASE is in the range [-2**213, 2**213).
    // By the soundness assumption, val.d0 is in the range (-2**250, 2**250).
    // This implies that r1 * BASE = val.d0 + q * SECP_REM (as integers).

    tempvar r2 = (val.d1 + r1) / BASE;
    assert [range_check_ptr + 2] = r2 + 2 ** 127;
    // Similarly, this implies that r2 * BASE = val.d1 + r1 (as integers).
    // Therefore, r2 * BASE**2 = val.d1 * BASE + r1 * BASE.

    assert val.d2 = q * (BASE / 8) - r2;
    // Similarly, this implies that q * BASE / 4 = val.d2 + r2 (as integers).
    // Therefore,
    //   q * BASE**3 / 4 = val.d2 * BASE**2 + r2 * BASE ** 2 =
    //   val.d2 * BASE**2 + val.d1 * BASE + r1 * BASE =
    //   val.d2 * BASE**2 + val.d1 * BASE + val.d0 + q * SECP_REM =
    //   val + q * SECP_REM.
    // Hence, val = q * (BASE**3 / 4 - SECP_REM) = q * (2**256 - SECP_REM) = q * secp256k1_prime.

    let range_check_ptr = range_check_ptr + 3;
    return ();
}

func main{range_check_ptr}() {
    let point_1 = EcPoint(BigInt3(512,2412,133), BigInt3(64,0,6546));
    let point_2 = EcPoint(BigInt3(7,8,123), BigInt3(1,7,465));

    let (slope) = compute_slope(point_1, point_2);
    assert slope = BigInt3(32565103718045841981942279,60662980405630750722698303,6577829329490861459174478);
    return ();
}
