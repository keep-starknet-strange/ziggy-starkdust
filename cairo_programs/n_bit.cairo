%builtins range_check

func get_quad_bit{range_check_ptr}(scalar_u: felt, scalar_v: felt, m: felt) -> felt {
    alloc_locals;
    local quad_bit: felt;
    %{
        ids.quad_bit = (
            8 * ((ids.scalar_v >> ids.m) & 1)
            + 4 * ((ids.scalar_u >> ids.m) & 1)
            + 2 * ((ids.scalar_v >> (ids.m - 1)) & 1)
            + ((ids.scalar_u >> (ids.m - 1)) & 1)
        )
    %}
    return quad_bit;
}

func get_dibit{range_check_ptr}(scalar_u: felt, scalar_v: felt, m: felt) -> felt {
    alloc_locals;
    local dibit: felt;
    %{ ids.dibit = ((ids.scalar_u >> ids.m) & 1) + 2 * ((ids.scalar_v >> ids.m) & 1) %}
    return dibit;
}

func test_quad_bit{range_check_ptr}() {
    let u = 4194304;  // 1 << 22
    let v = 8388608;  // 1 << 23

    // 8 * 1 + 4 * 0 + 2 * 0 + 1 * 1
    assert get_quad_bit(u, v, 23) = 9;
    // 2 * 1 + 1 * 0
    assert get_dibit(u, v, 23) = 2;

    return ();
}

func main{range_check_ptr}() {
    test_quad_bit();

    return ();
}
