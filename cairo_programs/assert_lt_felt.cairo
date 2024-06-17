%builtins range_check

from starkware.cairo.common.math import assert_lt
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.math import assert_lt_felt

func assert_lt_felt_manual_implementation{range_check_ptr}(a, b) {
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.a)
        assert_integer(ids.b)
        assert (ids.a % PRIME) < (ids.b % PRIME), \
            f'a = {ids.a % PRIME} is not less than b = {ids.b % PRIME}.'
    %}
    alloc_locals;
    let (local a_high, local a_low) = split_felt(a);
    let (b_high, b_low) = split_felt(b);

    if (a_high == b_high) {
        assert_lt(a_low, b_low);
        return ();
    }
    assert_lt(a_high, b_high);
    return ();
}

func main{range_check_ptr: felt}() {
    let x = 5;
    let y = 6;

    tempvar m = 7;
    tempvar n = 7 * 7;

    assert_lt_felt(1, 2);
    assert_lt_felt(-2, -1);
    assert_lt_felt(1, -1);
    assert_lt_felt(0, 1);
    assert_lt_felt(x, y);
    assert_lt_felt(m, n);

    assert_lt_felt_manual_implementation(1, 2);
    assert_lt_felt_manual_implementation(-2, -1);
    assert_lt_felt_manual_implementation(1, -1);
    assert_lt_felt_manual_implementation(0, 1);
    assert_lt_felt_manual_implementation(x, y);
    assert_lt_felt_manual_implementation(m, n);

    return ();
}
