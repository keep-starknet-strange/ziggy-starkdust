%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import BigInt3, BASE

// Hint arguments: value.
func nondet_bigint3{range_check_ptr}() -> (res: BigInt3) {
    // The result should be at the end of the stack after the function returns.
    let res: BigInt3 = [cast(ap + 5, BigInt3*)];
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import split
        segments.write_arg(ids.res.address_, split(value))
    %}
    // The maximal possible sum of the limbs, assuming each of them is in the range [0, BASE).
    const MAX_SUM = 3 * (BASE - 1);
    assert [range_check_ptr] = MAX_SUM - (res.d0 + res.d1 + res.d2);

    // Prepare the result at the end of the stack.
    tempvar range_check_ptr = range_check_ptr + 4;
    [range_check_ptr - 3] = res.d0, ap++;
    [range_check_ptr - 2] = res.d1, ap++;
    [range_check_ptr - 1] = res.d2, ap++;
    static_assert &res + BigInt3.SIZE == ap;
    return (res=res);
}

func main{range_check_ptr}() {
    alloc_locals;
    // Take these hints from div_mod_n just to have a value in scope
    local a: BigInt3 = BigInt3(1,2,3);
    local b: BigInt3 = BigInt3(4,5,6);
    %{
        from starkware.cairo.common.cairo_secp.secp_utils import N, pack
        from starkware.python.math_utils import div_mod, safe_div

        a = pack(ids.a, PRIME)
        b = pack(ids.b, PRIME)
        value = res = div_mod(a, b, N)
    %}
    let (r) = nondet_bigint3();
    assert r.d0 = 46511138620617205537268188;
    assert r.d1 = 26286155657000021849694253;
    assert r.d2 = 3102515549921694024741409;
    return();
}

