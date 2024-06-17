%builtins range_check

from starkware.cairo.common.cairo_secp.bigint import BigInt3

func get_highlen{range_check_ptr}(scalar_u: BigInt3, scalar_v: BigInt3) -> felt {
    alloc_locals;
    local len_hi;

    %{ ids.len_hi = max(ids.scalar_u.d2.bit_length(), ids.scalar_v.d2.bit_length())-1 %}

    return len_hi;
}

func test_highest_len{range_check_ptr}() {
    assert get_highlen(BigInt3(0, 0, 8), BigInt3(0, 0, 0)) = 3;
    assert get_highlen(BigInt3(0, 0, 0), BigInt3(0, 0, 1)) = 0;
    assert get_highlen(BigInt3(0, 0, 2), BigInt3(0, 0, 1)) = 1;

    // This overflows
    let res = get_highlen(BigInt3(0, 0, 0), BigInt3(0, 0, 0));
    assert res = 3618502788666131213697322783095070105623107215331596699973092056135872020480;

    return ();
}

func main{range_check_ptr}() {
    test_highest_len();

    return ();
}
