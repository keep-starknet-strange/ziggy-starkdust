%builtins range_check
from starkware.cairo.common.math import split_felt, assert_le, assert_nn_le

// Asserts that the unsigned integer lift (as a number in the range [0, PRIME)) of a is lower than
// or equal to that of b.
// See split_felt() for more details.
func assert_le_felt_v_0_6{range_check_ptr}(a, b) {
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.a)
        assert_integer(ids.b)
        assert (ids.a % PRIME) <= (ids.b % PRIME), \
            f'a = {ids.a % PRIME} is not less than or equal to b = {ids.b % PRIME}.'
    %}
    alloc_locals;
    let (local a_high, local a_low) = split_felt(a);
    let (b_high, b_low) = split_felt(b);

    if (a_high == b_high) {
        assert_le(a_low, b_low);
        return ();
    }
    assert_le(a_high, b_high);
    return ();
}

// Asserts that the unsigned integer lift (as a number in the range [0, PRIME)) of a is lower than
// or equal to that of b.
// See split_felt() for more details.
@known_ap_change
func assert_le_felt_v_0_8{range_check_ptr}(a, b) {
    alloc_locals;
    local small_inputs;
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.a)
        assert_integer(ids.b)
        a = ids.a % PRIME
        b = ids.b % PRIME
        assert a <= b, f'a = {a} is not less than or equal to b = {b}.'

        ids.small_inputs = int(
            a < range_check_builtin.bound and (b - a) < range_check_builtin.bound)
    %}
    if (small_inputs != 0) {
        assert_nn_le(a, b);
        ap += 33;
        return ();
    }

    let (local a_high, local a_low) = split_felt(a);
    let (b_high, b_low) = split_felt(b);

    if (a_high == b_high) {
        assert_le(a_low, b_low);
        return ();
    }

    assert_le(a_high, b_high);
    return ();
}

func main{range_check_ptr}() {
    assert_le_felt_v_0_6(7, 17);
    assert_le_felt_v_0_8(6, 16);
    assert_le_felt_v_0_8(5, -15);
    return();
}
