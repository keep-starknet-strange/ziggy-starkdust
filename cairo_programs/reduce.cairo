%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import BigInt3, UnreducedBigInt3, nondet_bigint3

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

// Receives an unreduced number, and returns a number that is equal to the original number mod
// Ed25519 prime and in reduced form (meaning every limb is in the range [0, BASE)).
//
// Completeness assumption: x's limbs are in the range (-2**210.99, 2**210.99).
// Soundness assumption: x's limbs are in the range (-2**249.99, 2**249.99).
func reduce_ed25519{range_check_ptr}(x: UnreducedBigInt3) -> (reduced_x: BigInt3) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        SECP_P=2**255-19

        value = pack(ids.x, PRIME) % SECP_P
    %}
    let (reduced_x: BigInt3) = nondet_bigint3();

    verify_zero(
        UnreducedBigInt3(d0=x.d0 - reduced_x.d0, d1=x.d1 - reduced_x.d1, d2=x.d2 - reduced_x.d2)
    );
    return (reduced_x=reduced_x);
}

func test_reduce_ed25519{range_check_ptr}() {
    let x = UnreducedBigInt3(0, 0, 0);
    let (res) = reduce_ed25519(x);
    assert res = BigInt3(0, 0, 0);

    let x = UnreducedBigInt3(
        1113660525233188137217661511617697775365785011829423399545361443,
        1243997169368861650657124871657865626433458458266748922940703512,
        1484456708474143440067316914074363277495967516029110959982060577,
    );
    let (res) = reduce_ed25519(x);
    assert res = BigInt3(
        42193159084937489098474581, 19864776835133205750023223, 916662843592479469328893
    );

    return ();
}

func reduce_v2{range_check_ptr}(x: UnreducedBigInt3) -> (reduced_x: BigInt3) {
    let orig_x = x;
    %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P %}
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        value = pack(ids.x, PRIME) % SECP_P
    %}
    let (reduced_x: BigInt3) = nondet_bigint3();

    verify_zero(
        UnreducedBigInt3(
            d0=orig_x.d0 - reduced_x.d0,
            d1=orig_x.d1 - reduced_x.d1,
            d2=orig_x.d2 - reduced_x.d2
        )
    );
    return (reduced_x=reduced_x);
}

func main{range_check_ptr}() {
    test_reduce_ed25519();

    // reduce_v2 tests
    let x = UnreducedBigInt3(0, 0, 0);
    let (reduce_v2_a) = reduce_v2(x);
    assert reduce_v2_a = BigInt3(
        0, 0, 0
    );

    let y = UnreducedBigInt3(12354, 745634534, 81298789312879123);
    let (reduce_v2_b) = reduce_v2(y);
    assert reduce_v2_b = BigInt3(
        12354, 745634534, 81298789312879123
    );

    let z = UnreducedBigInt3(12354812987893128791212331231233, 7453123123123123312634534, 8129224990312325879);
    let (reduce_v2_c) = reduce_v2(z);
    assert reduce_v2_c = BigInt3(
        16653320122975184709085185, 7453123123123123312794216, 8129224990312325879
    );
    return ();
}
