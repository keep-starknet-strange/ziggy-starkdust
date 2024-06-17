%builtins range_check

// Source: https://github.com/NilFoundation/cairo-placeholder-verification/blob/382924c6f1c4f9673a12a31d19835e00978ab241/src/signatures/ed25519.cairo

from starkware.cairo.common.cairo_secp.bigint import BASE, BigInt3, bigint_mul, nondet_bigint3
from starkware.cairo.common.cairo_secp.constants import N0, N1, N2
from starkware.cairo.common.cairo_secp.ec import EcPoint, ec_add, ec_mul

from starkware.cairo.common.math import assert_nn_le, assert_not_zero

// Computes x * s^(-1) modulo the size of the elliptic curve (N).
func mul_s_inv{range_check_ptr}(x : BigInt3, s : BigInt3) -> (res : BigInt3){
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        from starkware.python.math_utils import div_mod, safe_div

        N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141
        x = pack(ids.x, PRIME) % N
        s = pack(ids.s, PRIME) % N
        value = res = div_mod(x, s, N)
    %}
    let (res) = nondet_bigint3();

    %{ value = k = safe_div(res * s - x, N) %}
    let (k) = nondet_bigint3();

    let (res_s) = bigint_mul(res, s);
    let n = BigInt3(N0, N1, N2);
    let (k_n) = bigint_mul(k, n);

    // We should now have res_s = k_n + x. Since the numbers are in unreduced form,
    // we should handle the carry.

    tempvar carry1 = (res_s.d0 - k_n.d0 - x.d0) / BASE;
    assert [range_check_ptr + 0] = carry1 + 2 ** 127;

    tempvar carry2 = (res_s.d1 - k_n.d1 - x.d1 + carry1) / BASE;
    assert [range_check_ptr + 1] = carry2 + 2 ** 127;

    tempvar carry3 = (res_s.d2 - k_n.d2 - x.d2 + carry2) / BASE;
    assert [range_check_ptr + 2] = carry3 + 2 ** 127;

    tempvar carry4 = (res_s.d3 - k_n.d3 + carry3) / BASE;
    assert [range_check_ptr + 3] = carry4 + 2 ** 127;

    assert res_s.d4 - k_n.d4 + carry4 = 0;

    let range_check_ptr = range_check_ptr + 4;

    return (res=res);
}

func main{range_check_ptr} () -> (){
    alloc_locals;
    let bi1 = BigInt3(0x216936D3CD6E53FEC0A4E, 0x231FDD6DC5C692CC760952, 0x5A7B2C9562D608F25D51A);
    let bi2 = BigInt3(0x666666666666666666666, 0x6666666666666666666666, 0x666666666666666666658);
    let res = mul_s_inv(bi1, bi2);
    assert res = res;
    return ();
}
