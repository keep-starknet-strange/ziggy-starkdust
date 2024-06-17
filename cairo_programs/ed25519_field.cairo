%builtins range_check

// Source: https://github.com/NilFoundation/cairo-ed25519/blob/fee64a1a60b2e07b3b5c20df57f31d7ffcb29ac9/ed25519_field.cairo

from starkware.cairo.common.cairo_secp.bigint import BASE, BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.constants import SECP_REM

// Verifies that the given unreduced value is equal to zero modulo the secp256k1 prime.
// Completeness assumption: val's limbs are in the range (-2**210.99, 2**210.99).
// Soundness assumption: val's limbs are in the range (-2**250, 2**250).
func verify_zero{range_check_ptr}(val: UnreducedBigInt3) {
    let x = val;
    // Used just to import pack in scope
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        value = pack(ids.x, PRIME) % SECP_P
    %}
    nondet_bigint3();

    let q = [ap];
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P
        q, r = divmod(pack(ids.val, PRIME), SECP_P)
        assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
        ids.q = q % PRIME
    %}
    let q_biased = [ap + 1];
    q_biased = q + 2 ** 127, ap++;
    [range_check_ptr] = q_biased, ap++;

    tempvar r1 = (val.d0 + q * SECP_REM) / BASE;
    assert [range_check_ptr + 1] = r1 + 2 ** 127;
    // This implies r1 * BASE = val.d0 + q * SECP_REM (as integers).

    tempvar r2 = (val.d1 + r1) / BASE;
    assert [range_check_ptr + 2] = r2 + 2 ** 127;
    // This implies r2 * BASE = val.d1 + r1 (as integers).
    // Therefore, r2 * BASE**2 = val.d1 * BASE + r1 * BASE.

    assert val.d2 = q * (BASE / 4) - r2;
    // This implies q * BASE / 4 = val.d2 + r2 (as integers).
    // Therefore,
    //   q * BASE**3 / 4 = val.d2 * BASE**2 + r2 * BASE ** 2 =
    //   val.d2 * BASE**2 + val.d1 * BASE + r1 * BASE =
    //   val.d2 * BASE**2 + val.d1 * BASE + val.d0 + q * SECP_REM =
    //   val + q * SECP_REM.
    // Hence, val = q * (BASE**3 / 4 - SECP_REM) = q * (2**256 - SECP_REM).

    let range_check_ptr = range_check_ptr + 3;
    return ();
}

// Source: https://github.com/myBraavos/efficient-secp256r1/blob/73cca4d53730cb8b2dcf34e36c7b8f34b96b3230/src/secp256r1/ec.cairo#L106
func verify_zero_alt{range_check_ptr}(val: UnreducedBigInt3) {
    let x = val;
    // Used just to import SECP_P in scope
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        value = pack(ids.x, PRIME) % SECP_P
    %}
    nondet_bigint3();

    let q = [ap];
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack

        q, r = divmod(pack(ids.val, PRIME), SECP_P)
        assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
        ids.q = q % PRIME
    %}
    let q_biased = [ap + 1];
    q_biased = q + 2 ** 127, ap++;
    [range_check_ptr] = q_biased, ap++;

    tempvar r1 = (val.d0 + q * SECP_REM) / BASE;
    assert [range_check_ptr + 1] = r1 + 2 ** 127;
    // This implies r1 * BASE = val.d0 + q * SECP_REM (as integers).

    tempvar r2 = (val.d1 + r1) / BASE;
    assert [range_check_ptr + 2] = r2 + 2 ** 127;
    // This implies r2 * BASE = val.d1 + r1 (as integers).
    // Therefore, r2 * BASE**2 = val.d1 * BASE + r1 * BASE.

    assert val.d2 = q * (BASE / 4) - r2;
    // This implies q * BASE / 4 = val.d2 + r2 (as integers).
    // Therefore,
    //   q * BASE**3 / 4 = val.d2 * BASE**2 + r2 * BASE ** 2 =
    //   val.d2 * BASE**2 + val.d1 * BASE + r1 * BASE =
    //   val.d2 * BASE**2 + val.d1 * BASE + val.d0 + q * SECP_REM =
    //   val + q * SECP_REM.
    // Hence, val = q * (BASE**3 / 4 - SECP_REM) = q * (2**256 - SECP_REM).

    let range_check_ptr = range_check_ptr + 3;
    return ();
}

func test_verify_zero{range_check_ptr: felt}() {
    let val = UnreducedBigInt3(0, 0, 0);

    verify_zero(val);

    return ();
}

func test_verify_zero_alt{range_check_ptr: felt}() {
    let val = UnreducedBigInt3(0, 0, 0);

    verify_zero_alt(val);

    return ();
}

func main{range_check_ptr: felt}() {
    test_verify_zero();
    test_verify_zero_alt();

    return ();
}
