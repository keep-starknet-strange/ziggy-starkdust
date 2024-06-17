%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import BigInt3, nondet_bigint3, BASE, bigint_mul
from starkware.cairo.common.cairo_secp.constants import BETA, N0, N1, N2

// Source: https://github.com/myBraavos/efficient-secp256r1/blob/73cca4d53730cb8b2dcf34e36c7b8f34b96b3230/src/secp256r1/signature.cairo

// Computes a * b^(-1) modulo the size of the elliptic curve (N).
//
// Prover assumptions:
// * All the limbs of a are in the range (-2 ** 210.99, 2 ** 210.99).
// * All the limbs of b are in the range (-2 ** 124.99, 2 ** 124.99).
// * b is in the range [0, 2 ** 256).
//
// Soundness assumptions:
// * The limbs of a are in the range (-2 ** 249, 2 ** 249).
// * The limbs of b are in the range (-2 ** 159.83, 2 ** 159.83).
func div_mod_n{range_check_ptr}(a: BigInt3, b: BigInt3) -> (res: BigInt3) {
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import N, pack
        from starkware.python.math_utils import div_mod, safe_div

        a = pack(ids.a, PRIME)
        b = pack(ids.b, PRIME)
        value = res = div_mod(a, b, N)
    %}
    let (res) = nondet_bigint3();

    %{ value = k_plus_one = safe_div(res * b - a, N) + 1 %}
    let (k_plus_one) = nondet_bigint3();
    let k = BigInt3(d0=k_plus_one.d0 - 1, d1=k_plus_one.d1, d2=k_plus_one.d2);

    let (res_b) = bigint_mul(res, b);
    let n = BigInt3(N0, N1, N2);
    let (k_n) = bigint_mul(k, n);

    // We should now have res_b = k_n + a. Since the numbers are in unreduced form,
    // we should handle the carry.

    tempvar carry1 = (res_b.d0 - k_n.d0 - a.d0) / BASE;
    assert [range_check_ptr + 0] = carry1 + 2 ** 127;

    tempvar carry2 = (res_b.d1 - k_n.d1 - a.d1 + carry1) / BASE;
    assert [range_check_ptr + 1] = carry2 + 2 ** 127;

    tempvar carry3 = (res_b.d2 - k_n.d2 - a.d2 + carry2) / BASE;
    assert [range_check_ptr + 2] = carry3 + 2 ** 127;

    tempvar carry4 = (res_b.d3 - k_n.d3 + carry3) / BASE;
    assert [range_check_ptr + 3] = carry4 + 2 ** 127;

    assert res_b.d4 - k_n.d4 + carry4 = 0;

    let range_check_ptr = range_check_ptr + 4;

    return (res=res);
}

func div_mod_n_alt{range_check_ptr}(a: BigInt3, b: BigInt3) -> (res: BigInt3) {
    // just used to import N
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import N, pack
        from starkware.python.math_utils import div_mod, safe_div

        a = pack(ids.a, PRIME)
        b = pack(ids.b, PRIME)
        value = res = div_mod(a, b, N)
    %}

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        from starkware.python.math_utils import div_mod, safe_div

        a = pack(ids.a, PRIME)
        b = pack(ids.b, PRIME)
        value = res = div_mod(a, b, N)
    %}
    let (res) = nondet_bigint3();

    %{ value = k_plus_one = safe_div(res * b - a, N) + 1 %}
    let (k_plus_one) = nondet_bigint3();
    let k = BigInt3(d0=k_plus_one.d0 - 1, d1=k_plus_one.d1, d2=k_plus_one.d2);

    let (res_b) = bigint_mul(res, b);
    let n = BigInt3(N0, N1, N2);
    let (k_n) = bigint_mul(k, n);

    tempvar carry1 = (res_b.d0 - k_n.d0 - a.d0) / BASE;
    assert [range_check_ptr + 0] = carry1 + 2 ** 127;

    tempvar carry2 = (res_b.d1 - k_n.d1 - a.d1 + carry1) / BASE;
    assert [range_check_ptr + 1] = carry2 + 2 ** 127;

    tempvar carry3 = (res_b.d2 - k_n.d2 - a.d2 + carry2) / BASE;
    assert [range_check_ptr + 2] = carry3 + 2 ** 127;

    tempvar carry4 = (res_b.d3 - k_n.d3 + carry3) / BASE;
    assert [range_check_ptr + 3] = carry4 + 2 ** 127;

    assert res_b.d4 - k_n.d4 + carry4 = 0;

    let range_check_ptr = range_check_ptr + 4;

    return (res=res);
}

func test_div_mod_n{range_check_ptr: felt}() {
    let a: BigInt3 = BigInt3(100, 99, 98);
    let b: BigInt3 = BigInt3(10, 9, 8);

    let (res) = div_mod_n(a, b);

    assert res = BigInt3(
        3413472211745629263979533, 17305268010345238170172332, 11991751872105858217578135
    );

    // test alternative hint
    let (res_alt) = div_mod_n_alt(a, b);

    assert res_alt = res;

    return ();
}

func main{range_check_ptr: felt}() {
    test_div_mod_n();

    return ();
}
