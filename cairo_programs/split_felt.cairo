%builtins range_check

from starkware.cairo.common.math import assert_le
from starkware.cairo.common.math import split_felt

func split_felt_manual_implemetation{range_check_ptr}(value) -> (high: felt, low: felt) {
    // Note: the following code works because PRIME - 1 is divisible by 2**128.
    const MAX_HIGH = (-1) / 2 ** 128;
    const MAX_LOW = 0;

    // Guess the low and high parts of the integer.
    let low = [range_check_ptr];
    let high = [range_check_ptr + 1];
    let range_check_ptr = range_check_ptr + 2;

    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert ids.MAX_HIGH < 2**128 and ids.MAX_LOW < 2**128
        assert PRIME - 1 == ids.MAX_HIGH * 2**128 + ids.MAX_LOW
        assert_integer(ids.value)
        ids.low = ids.value & ((1 << 128) - 1)
        ids.high = ids.value >> 128
    %}

    assert value = high * (2 ** 128) + low;
    if (high == MAX_HIGH) {
        assert_le(low, MAX_LOW);
    } else {
        assert_le(high, MAX_HIGH - 1);
    }
    return (high=high, low=low);
}

func main{range_check_ptr: felt}() {
    let (m, n) = split_felt_manual_implemetation(5784800237655953878877368326340059594760);
    assert m = 17;
    assert n = 8;
    let (x, y) = split_felt(5784800237655953878877368326340059594760);
    assert x = 17;
    assert y = 8;
    return ();
}
