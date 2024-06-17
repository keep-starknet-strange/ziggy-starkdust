%builtins range_check
from starkware.cairo.common.math import unsigned_div_rem

func unsigned_div_rem_man{range_check_ptr}(value, div) -> (q: felt, r: felt) {
    let r = [range_check_ptr];
    let q = [range_check_ptr + 1];
    let range_check_ptr = range_check_ptr + 2;
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.div)
        assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
            f'div={hex(ids.div)} is out of the valid range.'
        ids.q, ids.r = divmod(ids.value, ids.div)
    %}

    return (q, r);
}

func main{range_check_ptr: felt}() {
    let (q, r) = unsigned_div_rem_man(10, 3);
    let (expected_q, expected_r) = unsigned_div_rem(10, 3);
    assert q = expected_q;
    assert r = expected_r;
    assert q = 3;
    assert r = 1;
    return ();
}
