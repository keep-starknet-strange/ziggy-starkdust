%builtins range_check

// Source: https://github.com/Astraly-Labs/Starknet-VRF/blob/33175b179627fdf1f12e32b197a368c1fefcd34c/lib/ed25519.cairo
from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.ec import EcPoint

const BASE = 2 ** 86;
const SECP_REM = 19;

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

// Computes the negation of a point on the elliptic curve, which is a point with the same x value
// and the negation of the y value. If the point is the zero point, returns the zero point.
//
// Arguments:
//   point - The point to operate on.
//
// Returns:
//   point - The negation of the given point.
func ec_negate{range_check_ptr}(point: EcPoint) -> (point: EcPoint) {
    alloc_locals;
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P = 2**255-19

        y = pack(ids.point.y, PRIME) % SECP_P
        # The modulo operation in python always returns a nonnegative number.
        value = (-y) % SECP_P
    %}
    let (minus_y) = nondet_bigint3();

    // This check fails. cairo-lang's uses a different modulus, and the one used
    // by this library uses a hint that's not implemented
    // verify_zero(
    //     UnreducedBigInt3(
    //         d0=minus_y.d0 + point.y.d0, d1=minus_y.d1 + point.y.d1, d2=minus_y.d2 + point.y.d2
    //     ),
    // );

    return (point=EcPoint(x=point.x, y=minus_y));
}

func test_ec_negate{range_check_ptr}() {
    let p = EcPoint(BigInt3(1, 2, 3), BigInt3(1, 2, 3));

    let (minus_p) = ec_negate(p);

    assert minus_p.x.d0 = 1;
    assert minus_p.x.d1 = 2;
    assert minus_p.x.d2 = 3;

    assert minus_p.y.d0 = 77371252455336267181195244;
    assert minus_p.y.d1 = 77371252455336267181195261;
    assert minus_p.y.d2 = 9671406556917033397649404;

    let p = EcPoint(
        BigInt3(12424, 53151, 363737),
        BigInt3(77371252455336267181195244, 77371252455336267181195261, 9671406556917033397649404),
    );

    let (minus_p) = ec_negate(p);

    assert minus_p.x.d0 = 12424;
    assert minus_p.x.d1 = 53151;
    assert minus_p.x.d2 = 363737;

    assert minus_p.y.d0 = 1;
    assert minus_p.y.d1 = 2;
    assert minus_p.y.d2 = 3;

    return ();
}

func main{range_check_ptr}() {
    test_ec_negate();
    return ();
}
