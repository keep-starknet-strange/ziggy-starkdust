%builtins range_check

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.pow import pow
from starkware.cairo.common.math_cmp import (
    is_not_zero,
    is_nn,
    is_le,
    is_nn_le,
    is_in_range,
    is_le_felt,
)

const CONSTANT = 3 ** 10;

func fill_array_with_pow{range_check_ptr}(
    array_start: felt*, base: felt, step: felt, exp: felt, iter: felt, last: felt
) -> () {
    if (iter == last) {
        return ();
    }
    let (res) = pow(base + step, exp);
    assert array_start[iter] = res;
    return fill_array_with_pow(array_start, base + step, step, exp, iter + 1, last);
}

func test_is_not_zero{range_check_ptr}(
    base_array: felt*, new_array: felt*, iter: felt, last: felt
) -> () {
    if (iter == last) {
        return ();
    }
    let res = is_not_zero(base_array[iter]);
    assert new_array[iter] = res;
    return test_is_not_zero(base_array, new_array, iter + 1, last);
}

func test_is_nn{range_check_ptr}(base_array: felt*, new_array: felt*, iter: felt, last: felt) -> (
    ) {
    if (iter == last) {
        return ();
    }
    let res = is_nn(base_array[iter]);
    assert new_array[iter] = res;
    return test_is_nn(base_array, new_array, iter + 1, last);
}

func test_is_le{range_check_ptr}(base_array: felt*, new_array: felt*, iter: felt, last: felt) -> (
    ) {
    if (iter == last) {
        return ();
    }
    let res = is_le(base_array[iter], CONSTANT);
    assert new_array[iter] = res;
    return test_is_le(base_array, new_array, iter + 1, last);
}

func test_is_nn_le{range_check_ptr}(
    base_array: felt*, new_array: felt*, iter: felt, last: felt
) -> () {
    if (iter == last) {
        return ();
    }
    let res = is_nn_le(base_array[iter], CONSTANT);
    assert new_array[iter] = res;
    return test_is_nn_le(base_array, new_array, iter + 1, last);
}

func test_is_in_range{range_check_ptr}(
    base_array: felt*, new_array: felt*, iter: felt, last: felt
) -> () {
    if (iter == last) {
        return ();
    }
    let res = is_in_range(CONSTANT, base_array[iter], base_array[iter + 1]);
    assert new_array[iter] = res;
    return test_is_in_range(base_array, new_array, iter + 1, last);
}

func test_is_le_felt{range_check_ptr}(
    base_array: felt*, new_array: felt*, iter: felt, last: felt
) -> () {
    if (iter == last) {
        return ();
    }
    let res = is_le_felt(base_array[iter], CONSTANT);
    assert new_array[iter] = res;
    return test_is_le_felt(base_array, new_array, iter + 1, last);
}

func run_tests{range_check_ptr}(array_len: felt) -> () {
    alloc_locals;
    let (array: felt*) = alloc();
    fill_array_with_pow(array, 0, 3, 3, 0, array_len);

    let (array_is_not_zero: felt*) = alloc();
    test_is_not_zero(array, array_is_not_zero, 0, array_len);

    let (array_is_nn: felt*) = alloc();
    test_is_nn(array, array_is_nn, 0, array_len);

    let (array_is_le: felt*) = alloc();
    test_is_le(array, array_is_le, 0, array_len);

    let (array_is_nn_le: felt*) = alloc();
    test_is_nn_le(array, array_is_nn_le, 0, array_len);

    let (array_is_in_range: felt*) = alloc();
    test_is_in_range(array, array_is_in_range, 0, array_len - 1);

    let (array_is_le_felt: felt*) = alloc();
    test_is_le_felt(array, array_is_le_felt, 0, array_len);

    return ();
}

func main{range_check_ptr}() {
    run_tests(10);
    return ();
}
