%builtins range_check

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_not_equal,
    assert_nn,
    assert_le,
    assert_lt,
    assert_nn_le,
    assert_in_range,
    assert_250_bit,
    split_felt,
    assert_le_felt,
    assert_lt_felt,
    abs_value,
    sign,
    unsigned_div_rem,
    signed_div_rem,
    split_int,
    sqrt,
    horner_eval,
)

func fill_array(array_start: felt*, base: felt, step: felt, iter: felt, last: felt) -> () {
    if (iter == last) {
        return ();
    }
    assert array_start[iter] = base + step;
    return fill_array(array_start, base + step, step, iter + 1, last);
}

func test_assert_nn{range_check_ptr}(array_start: felt*, iter: felt, last: felt) -> () {
    if (iter == last) {
        return ();
    }
    assert_nn(array_start[iter]);
    return test_assert_nn(array_start, iter + 1, last);
}

func test_assert_not_zero(array_start: felt*, iter: felt, last: felt) -> () {
    if (iter == last) {
        return ();
    }
    assert_not_zero(array_start[iter]);
    return test_assert_not_zero(array_start, iter + 1, last);
}

func test_assert_not_equal(array_a: felt*, array_b: felt*, iter: felt, size: felt) -> () {
    if (iter == size) {
        return ();
    }
    assert_not_equal(array_a[iter], array_b[iter]);
    return test_assert_not_equal(array_a, array_b, iter + 1, size);
}

func test_assert_le{range_check_ptr}(array_a: felt*, array_b: felt*, iter: felt, size: felt) -> () {
    if (iter == size) {
        return ();
    }
    assert_le(array_a[iter], array_b[iter]);
    return test_assert_le(array_a, array_b, iter + 1, size);
}

func test_assert_lt{range_check_ptr}(array_a: felt*, array_b: felt*, iter: felt, size: felt) -> () {
    if (iter == size) {
        return ();
    }
    assert_lt(array_a[iter], array_b[iter]);
    return test_assert_lt(array_a, array_b, iter + 1, size);
}

func test_assert_nn_le{range_check_ptr}(array_a: felt*, array_b: felt*, iter: felt, size: felt) -> (
    ) {
    if (iter == size) {
        return ();
    }
    assert_nn_le(array_a[iter], array_b[iter]);
    return test_assert_nn_le(array_a, array_b, iter + 1, size);
}

func test_assert_in_range{range_check_ptr}(
    array_start: felt*, iter: felt, size: felt, lower: felt, upper: felt
) {
    if (iter == size) {
        return ();
    }
    assert_in_range{range_check_ptr=range_check_ptr}(array_start[iter], lower, upper);
    return test_assert_in_range{range_check_ptr=range_check_ptr}(
        array_start, iter + 1, size, lower, upper
    );
}

func test_assert_250_bit{range_check_ptr}(array_start: felt*, iter: felt, last: felt) -> () {
    if (iter == last) {
        return ();
    }
    assert_250_bit(array_start[iter]);
    return test_assert_250_bit(array_start, iter + 1, last);
}

func test_split_felt{range_check_ptr}(array_start: felt*, iter: felt, last: felt) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }
    let (x: felt, y: felt) = split_felt(array_start[iter]);
    assert array_start[iter] = x * (2 ** 128) + y;
    return test_split_felt(array_start, iter + 1, last);
}

func test_assert_le_felt{range_check_ptr}(
    array_a: felt*, array_b: felt*, iter: felt, last: felt
) -> () {
    if (iter == last) {
        return ();
    }
    assert_le_felt(array_a[iter], array_b[iter]);
    return test_assert_le_felt(array_a, array_b, iter + 1, last);
}

func test_assert_lt_felt{range_check_ptr}(
    array_a: felt*, array_b: felt*, iter: felt, last: felt
) -> () {
    if (iter == last) {
        return ();
    }
    assert_lt_felt(array_a[iter], array_b[iter]);
    return test_assert_lt_felt(array_a, array_b, iter + 1, last);
}

func test_abs_value{range_check_ptr}(array_a: felt*, array_b: felt*, iter: felt, last: felt) -> () {
    alloc_locals;
    if (iter == last) {
        return ();
    }
    let abs_a: felt = abs_value(array_a[iter]);
    let abs_b: felt = abs_value(array_b[iter]);
    assert abs_a = abs_b;
    return test_abs_value(array_a, array_b, iter + 1, last);
}

func test_same_sign{range_check_ptr}(array_a: felt*, array_b: felt*, iter: felt, last: felt) -> () {
    alloc_locals;
    if (iter == last) {
        return ();
    }
    let sign_a: felt = sign(array_a[iter]);
    let sign_b: felt = sign(array_b[iter]);
    assert sign_a = sign_b;
    return test_same_sign(array_a, array_b, iter + 1, last);
}

func test_diff_sign{range_check_ptr}(array_a: felt*, array_b: felt*, iter: felt, last: felt) -> () {
    alloc_locals;
    if (iter == last) {
        return ();
    }
    let sign_a: felt = sign(array_a[iter]);
    let sign_b: felt = sign(array_b[iter]);
    assert sign_a = -sign_b;
    return test_diff_sign(array_a, array_b, iter + 1, last);
}

func test_sqrt{range_check_ptr}(array_start: felt*, iter: felt, last: felt) -> () {
    alloc_locals;
    if (iter == last) {
        return ();
    }
    let n_sqrt: felt = sqrt(array_start[iter]);
    assert n_sqrt * n_sqrt = array_start[iter];
    return test_sqrt(array_start, iter + 1, last);
}

func test_split_int{range_check_ptr}(array_start: felt*, iter: felt, last: felt) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }
    let (output: felt*) = alloc();
    split_int(array_start[iter], 4, 8, 8, output);
    assert array_start[iter] = output[0] + output[1] * 8 + output[2] * 64 + output[3] * 512;
    return test_split_int(array_start, iter + 1, last);
}

func test_horner_eval{range_check_ptr}(array_start: felt*, iter: felt, last: felt) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }

    let res: felt = horner_eval(3, array_start + iter, 3);
    assert res = array_start[iter] + 3 * array_start[iter + 1] + 9 * array_start[iter + 2];
    return test_horner_eval(array_start, iter + 1, last);
}

func test_{range_check_ptr}(array_start: felt*, iter: felt, last: felt) -> () {
    if (iter == last) {
        return ();
    }
    // unsigned_div_rem{range_check_ptr}(value, div) -> (q : felt, r : felt):,
    // signed_div_rem{range_check_ptr}(value, div, bound) -> (q : felt, r : felt):,
    return test_(array_start, iter + 1, last);
}

func run_tests{range_check_ptr}(array_len: felt) -> () {
    alloc_locals;

    assert_lt(1, array_len);

    let (array: felt*) = alloc();
    fill_array(array, 0, 3, 0, array_len);

    let (array_neg: felt*) = alloc();
    fill_array(array_neg, 0, -3, 0, array_len);

    test_assert_nn(array, 0, array_len);
    // test_assert_nn(array_neg, 0, array_len)

    test_assert_not_zero(array, 1, array_len);
    test_assert_not_zero(array_neg, 1, array_len);

    test_assert_not_equal(array, array + 1, 0, array_len - 1);
    test_assert_not_equal(array + 1, array, 0, array_len - 1);
    test_assert_not_equal(array_neg, array_neg + 1, 0, array_len - 1);
    test_assert_not_equal(array_neg + 1, array_neg, 0, array_len - 1);

    test_assert_le(array, array, 0, array_len - 1);
    test_assert_le(array, array + 1, 0, array_len - 1);
    test_assert_lt(array, array + 1, 0, array_len - 1);
    test_assert_nn_le(array, array + 1, 0, array_len - 1);

    test_assert_le_felt(array, array, 0, array_len - 1);
    test_assert_le_felt(array, array + 1, 0, array_len - 1);
    test_assert_lt_felt(array, array + 1, 0, array_len - 1);

    test_abs_value(array, array, 0, array_len);
    test_abs_value(array_neg, array_neg, 0, array_len);
    test_abs_value(array_neg, array, 0, array_len);
    test_abs_value(array, array_neg, 0, array_len);

    test_same_sign(array, array, 0, array_len);
    test_same_sign(array + 1, array + 2, 0, array_len - 2);
    test_same_sign(array_neg, array_neg, 0, array_len);
    test_same_sign(array_neg + 1, array_neg + 2, 0, array_len - 2);

    test_diff_sign(array + 1, array_neg + 1, 0, array_len - 1);
    test_diff_sign(array_neg + 1, array + 1, 0, array_len - 1);

    // test_assert_in_range(array, 0, array_len, 0, array[array_len - 1])
    test_assert_250_bit(array, 0, array_len);
    test_split_felt(array, 0, array_len);
    test_split_int(array, 0, array_len);

    test_horner_eval(array, 0, array_len - 2);

    return ();
}

func main{range_check_ptr}() {
    run_tests(10);
    return ();
}
