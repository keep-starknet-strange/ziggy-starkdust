%builtins range_check

from starkware.starknet.common.storage import normalize_address
from starkware.cairo.common.math import assert_250_bit
from starkware.cairo.common.alloc import alloc

func normalize_address_element_array{range_check_ptr: felt}(
    array: felt*, array_length: felt, iterator: felt
) {
    if (iterator == array_length) {
        return ();
    }
    normalize_address(array[iterator]);
    return normalize_address_element_array(array, array_length, iterator + 1);
}

func fill_array(array: felt*, base: felt, step: felt, array_length: felt, iterator: felt) {
    if (iterator == array_length) {
        return ();
    }
    assert array[iterator] = base + step * iterator;
    return fill_array(array, base, step, array_length, iterator + 1);
}

func main{range_check_ptr: felt}() {
    alloc_locals;
    tempvar array_length = 10;
    let (array: felt*) = alloc();
    fill_array(array, 70000000000000000000, 300000000000000000, array_length, 0);
    normalize_address_element_array(array, array_length, 0);
    return ();
}
