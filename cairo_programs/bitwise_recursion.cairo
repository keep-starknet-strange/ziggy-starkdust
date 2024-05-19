%builtins output range_check bitwise

from starkware.cairo.common.bitwise import bitwise_and, bitwise_or, bitwise_xor
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.serialize import serialize_word

func distort_value{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}(
    value: felt, secondary_value: felt, loop_num: felt
) -> (r: felt) {
    if (loop_num == 0) {
        return (value,);
    }

    // Check that 0 <= secondary_value < 2**64.
    [range_check_ptr] = secondary_value;
    assert [range_check_ptr + 1] = 2 ** 64 - 1 - secondary_value;
    let range_check_ptr = range_check_ptr + 2;

    let (distorted_value_a) = bitwise_xor(value, secondary_value);
    let (distorted_value_b) = bitwise_or(value, secondary_value / 2);
    let (distorted_value) = bitwise_and(distorted_value_a, distorted_value_b);

    return distort_value(distorted_value, secondary_value * 3, loop_num - 1);
}

func main{output_ptr: felt*, range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() {
    let (result) = distort_value(45678783924002957984, 12546479, 20);
    assert result = 45673807582400916561;
    serialize_word(result);
    return ();
}
