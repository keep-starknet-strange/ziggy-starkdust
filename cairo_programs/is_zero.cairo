%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3
from starkware.cairo.common.cairo_secp.field import unreduced_mul, verify_zero

const BASE = 2 ** 86;
const SECP_REM = 19;

func verify_zero_ed25519{range_check_ptr}(val: UnreducedBigInt3) {
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

// Returns 1 if x == 0 (mod secp256k1_prime), and 0 otherwise.
//
// Completeness assumption: x's limbs are in the range (-BASE, 2*BASE).
// Soundness assumption: x's limbs are in the range (-2**107.49, 2**107.49).
func is_zero{range_check_ptr}(x: BigInt3) -> (res: felt) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        x = pack(ids.x, PRIME) % SECP_P
    %}
    if (nondet %{ x == 0 %} != 0) {
        verify_zero(UnreducedBigInt3(d0=x.d0, d1=x.d1, d2=x.d2));
        return (res=1);
    }

    %{
        from starkware.python.math_utils import div_mod

        value = x_inv = div_mod(1, x, SECP_P)
    %}
    let (x_inv) = nondet_bigint3();
    let (x_x_inv) = unreduced_mul(x, x_inv);

    // Check that x * x_inv = 1 to verify that x != 0.
    verify_zero(UnreducedBigInt3(d0=x_x_inv.d0 - 1, d1=x_x_inv.d1, d2=x_x_inv.d2));
    return (res=0);
}

func is_zero_alt{range_check_ptr}(x: BigInt3) -> (res: felt) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

        x = pack(ids.x, PRIME) % SECP_P
    %}
    %{ memory[ap] = int(x == 0) %}
    tempvar x_is_zero;

    if (x_is_zero != 0) {
        verify_zero(UnreducedBigInt3(d0=x.d0, d1=x.d1, d2=x.d2));
        return (res=1);
    }

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P
        from starkware.python.math_utils import div_mod

        value = x_inv = div_mod(1, x, SECP_P)
    %}
    let (x_inv) = nondet_bigint3();
    let (x_x_inv) = unreduced_mul(x, x_inv);

    // Check that x * x_inv = 1 to verify that x != 0.
    verify_zero(UnreducedBigInt3(d0=x_x_inv.d0 - 1, d1=x_x_inv.d1, d2=x_x_inv.d2));
    return (res=0);
}

// Returns 1 if x == 0 (mod secp256k1_prime), and 0 otherwise.
//
// Completeness assumption: x's limbs are in the range (-BASE, 2*BASE).
// Soundness assumption: x's limbs are in the range (-2**107.49, 2**107.49).
func is_zero_v2_pack{range_check_ptr}(x: BigInt3) -> (res: felt) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack
        x = pack(ids.x, PRIME) % SECP_P
    %}
    if (nondet %{ x == 0 %} != 0) {
        verify_zero(UnreducedBigInt3(d0=x.d0, d1=x.d1, d2=x.d2));
        return (res=1);
    }

    %{
        from starkware.python.math_utils import div_mod

        value = x_inv = div_mod(1, x, SECP_P)
    %}
    let (x_inv) = nondet_bigint3();
    let (x_x_inv) = unreduced_mul(x, x_inv);

    // Check that x * x_inv = 1 to verify that x != 0.
    verify_zero(UnreducedBigInt3(d0=x_x_inv.d0 - 1, d1=x_x_inv.d1, d2=x_x_inv.d2));
    return (res=0);
}

// Returns 1 if x == 0 (mod Ed25519 prime), and 0 otherwise.
//
// Completeness assumption: x's limbs are in the range (-BASE, 2*BASE).
// Soundness assumption: x's limbs are in the range (-2**107.49, 2**107.49).
func is_zero_ed25519{range_check_ptr}(x: BigInt3) -> (res: felt) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P=2**255-19

        x = pack(ids.x, PRIME) % SECP_P
    %}
    if (nondet %{ x == 0 %} != 0) {
        verify_zero_ed25519(UnreducedBigInt3(d0=x.d0, d1=x.d1, d2=x.d2));
        return (res=1);
    }

    %{
        SECP_P=2**255-19
        from starkware.python.math_utils import div_mod

        value = x_inv = div_mod(1, x, SECP_P)
    %}
    let (x_inv) = nondet_bigint3();
    let (x_x_inv) = unreduced_mul(x, x_inv);

    // Check that x * x_inv = 1 to verify that x != 0.
    verify_zero_ed25519(UnreducedBigInt3(d0=x_x_inv.d0 - 1, d1=x_x_inv.d1, d2=x_x_inv.d2));
    return (res=0);
}

func test_is_zero{range_check_ptr}() -> () {
    let zero = BigInt3(0, 0, 0);

    let (res: felt) = is_zero(zero);
    assert res = 1;

    let one = BigInt3(1, 0, 0);

    let (res: felt) = is_zero(one);
    assert res = 0;

    let secp256k1_prime = BigInt3(
        77371252455336262886226991, 77371252455336267181195263, 19342813113834066795298815
    );

    let (res: felt) = is_zero(secp256k1_prime);
    assert res = 1;

    return ();
}

func test_is_zero_alt{range_check_ptr}() -> () {
    let zero = BigInt3(0, 0, 0);

    let (res: felt) = is_zero_alt(zero);
    assert res = 1;

    let one = BigInt3(1, 0, 0);

    let (res: felt) = is_zero_alt(one);
    assert res = 0;

    let secp256k1_prime = BigInt3(
        77371252455336262886226991, 77371252455336267181195263, 19342813113834066795298815
    );

    let (res: felt) = is_zero_alt(secp256k1_prime);
    assert res = 1;

    return ();
}

func test_is_zero_v2_pack{range_check_ptr}() -> () {
    let zero = BigInt3(0, 0, 0);

    let (res: felt) = is_zero(zero);
    assert res = 1;

    let one = BigInt3(1, 0, 0);

    let (res: felt) = is_zero(one);
    assert res = 0;

    let secp256k1_prime = BigInt3(
        77371252455336262886226991, 77371252455336267181195263, 19342813113834066795298815
    );

    let (res: felt) = is_zero_v2_pack(secp256k1_prime);
    assert res = 1;

    return ();
}

func test_is_zero_ed25519{range_check_ptr}() -> () {
    let zero = BigInt3(0, 0, 0);

    let (res: felt) = is_zero_ed25519(zero);
    assert res = 1;

    let one = BigInt3(1, 0, 0);

    let (res: felt) = is_zero_ed25519(one);
    assert res = 0;

    let ed25519_prime = BigInt3(
        77371252455336267181195245, 77371252455336267181195263, 9671406556917033397649407
    );

    let (res: felt) = is_zero_ed25519(ed25519_prime);
    assert res = 1;

    return ();
}

func main{range_check_ptr}() -> () {
    test_is_zero();
    test_is_zero_alt();
    test_is_zero_v2_pack();
    test_is_zero_ed25519();

    return ();
}
