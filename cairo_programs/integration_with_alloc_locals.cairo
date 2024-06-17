%builtins output pedersen range_check bitwise

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.bitwise import bitwise_and, bitwise_or, bitwise_xor
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.serialize import serialize_word

func get_distorted_pedersen{hash_ptr: HashBuiltin*, bitwise_ptr: BitwiseBuiltin*}(
    num_a: felt, num_b: felt
) -> (r: felt) {
    let num_y: felt = bitwise_xor(num_a, num_b);
    let num_x: felt = bitwise_and(num_a, num_b);
    let pedersen_result: felt = hash2(num_x, num_y);
    return (pedersen_result,);
}

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

    let distorted_value_a: felt = bitwise_xor(value, secondary_value);
    let distorted_value_b: felt = bitwise_or(value, secondary_value / 2);
    let distorted_value: felt = bitwise_and(distorted_value_a, distorted_value_b);

    return distort_value(distorted_value, secondary_value * 3, loop_num - 1);
}

func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr: felt,
    bitwise_ptr: BitwiseBuiltin*,
}() {
    alloc_locals;
    tempvar num_a = 99;
    tempvar num_b = 105;
    let first_result: felt = get_distorted_pedersen{hash_ptr=pedersen_ptr}(num_a, num_b);
    let final_result: felt = distort_value(first_result, 17896542, 10);
    assert final_result = 1659553275753748707961758488122491333947144556174897006960881236685908158848;
    serialize_word(final_result);
    return ();
}
