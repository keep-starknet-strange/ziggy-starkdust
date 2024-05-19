%builtins range_check
from starkware.cairo.common.cairo_secp.bigint import BigInt3, nondet_bigint3

func test_div_mod_n_packed_hint{range_check_ptr: felt}() {

    tempvar n = BigInt3(177, 0, 0);
    tempvar x = BigInt3(25, 0, 0);
    tempvar s = BigInt3(5, 0, 0);

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        from starkware.python.math_utils import div_mod, safe_div

        N = pack(ids.n, PRIME)
        x = pack(ids.x, PRIME) % N
        s = pack(ids.s, PRIME) % N
        value = res = div_mod(x, s, N)
    %}

    let (res) = nondet_bigint3();
    assert res = BigInt3(5,0,0);

    return();
}

func test_sub_a_b_hint{range_check_ptr: felt}() {

    tempvar a = BigInt3(100, 0, 0);
    tempvar b = BigInt3(25, 0, 0);

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        from starkware.python.math_utils import div_mod, safe_div

        a = pack(ids.a, PRIME)
        b = pack(ids.b, PRIME)

        value = res = a - b
    %}

    let (res) = nondet_bigint3();
    assert res = BigInt3(75,0,0);

    return();
}

func test_product_hints{range_check_ptr: felt}() {

    tempvar a = BigInt3(60, 0, 0);
    tempvar b = BigInt3(2, 0, 0);
    tempvar m = BigInt3(100, 0, 0);

    %{
        from starkware.cairo.common.cairo_secp.secp_utils import pack
        from starkware.python.math_utils import div_mod, safe_div

        a = pack(ids.a, PRIME)
        b = pack(ids.b, PRIME)
        product = a * b
        m = pack(ids.m, PRIME)

        value = res = product % m
    %}

    let (res) = nondet_bigint3();
    assert res = BigInt3(20,0,0);

    %{
        value = k = product // m
    %}

    let (k) = nondet_bigint3();
    assert k = BigInt3(1,0,0);

    return();
}

func main{range_check_ptr: felt}() {
    test_div_mod_n_packed_hint();
    test_sub_a_b_hint();
    test_product_hints();
    return();
}
