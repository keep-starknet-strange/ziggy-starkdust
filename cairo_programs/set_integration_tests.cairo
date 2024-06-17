%builtins range_check

from starkware.cairo.common.set import set_add
from starkware.cairo.common.uint256 import Uint256, uint256_add
from starkware.cairo.common.alloc import alloc

func fill_uint256_array{range_check_ptr: felt}(
    array: Uint256*, base: Uint256, step: Uint256, array_len: felt, iterator: felt
) {
    if (iterator == array_len) {
        return ();
    }
    let (res: Uint256, carry_high: felt) = uint256_add(step, base);

    assert array[iterator] = res;
    return fill_uint256_array(array, base, array[iterator], array_len, iterator + 1);
}

// Create a set of Uint256 with the elements of base_array
func copy_uint256_set_from_array{range_check_ptr: felt}(
    set: Uint256*, base_array: Uint256*, set_len: felt, iterator: felt
) {
    if (iterator == set_len) {
        return ();
    }

    let set_end: felt* = &set[iterator];

    set_add{set_end_ptr=set_end}(set_ptr=set, elm_size=Uint256.SIZE, elm_ptr=&base_array[iterator]);

    return copy_uint256_set_from_array(
        set=set, base_array=base_array, set_len=set_len, iterator=iterator + 1
    );
}

func add_uint256_to_set{range_check_ptr: felt}(
    set: Uint256*, base_array: Uint256*, set_len: felt, iterator: felt
) {
    if (iterator == set_len) {
        return ();
    }

    let set_end: felt* = &set[set_len];
    set_add{set_end_ptr=set_end}(set_ptr=set, elm_size=Uint256.SIZE, elm_ptr=&base_array[iterator]);

    assert set[iterator] = base_array[iterator];

    return add_uint256_to_set(
        set=set, base_array=base_array, set_len=set_len, iterator=iterator + 1
    );
}

func check_uint256_set{range_check_ptr: felt}(
    set: Uint256*, base_array: Uint256*, set_len: felt, iterator: felt
) {
    if (iterator == set_len) {
        return ();
    }

    assert set[iterator] = base_array[iterator];

    return check_uint256_set(
        set=set, base_array=base_array, set_len=set_len, iterator=iterator + 1
    );
}

func run_tests{range_check_ptr}(array_len: felt) -> () {
    alloc_locals;
    // Create a Uint256 array
    let (uint256_array: Uint256*) = alloc();
    fill_uint256_array(uint256_array, Uint256(57, 8), Uint256(57, 101), array_len, 0);

    // Create a set of Uint256 with the elements of uint256_array
    // Since uint256_array has no repetead elements uint256_set == uint256_array
    let (uint256_set: Uint256*) = alloc();
    copy_uint256_set_from_array(uint256_set, uint256_array, array_len, 0);

    // Iter over the elements of uint256_array and try to add them to the uint256_set
    // Since uint256_array contains all the elements of uint256_array, No elements Should be added.
    add_uint256_to_set(set=uint256_set, base_array=uint256_array, set_len=array_len, iterator=0);

    // Check uint256_set == uint256_array
    check_uint256_set(set=uint256_set, base_array=uint256_array, set_len=array_len, iterator=0);

    return ();
}

func main{range_check_ptr: felt}() {
    run_tests(10);
    return ();
}
