%builtins range_check bitwise

from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    split_64,
    uint256_sqrt,
    uint256_signed_nn,
    uint256_unsigned_div_rem,
    uint256_mul,
    uint256_or,
    uint256_reverse_endian,
)
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func fill_array(array_start: felt*, base: felt, step: felt, iter: felt, last: felt) -> () {
    if (iter == last) {
        return ();
    }
    assert array_start[iter] = base + step;
    return fill_array(array_start, base + step, step, iter + 1, last);
}

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

func test_sqrt{range_check_ptr}(
    base_array: Uint256*, new_array: Uint256*, iter: felt, last: felt
) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }

    let res: Uint256 = uint256_sqrt(base_array[iter]);
    assert new_array[iter] = res;

    return test_sqrt(base_array, new_array, iter + 1, last);
}

func test_signed_nn{range_check_ptr}(
    base_array: Uint256*, new_array: felt*, iter: felt, last: felt
) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }

    let res: felt = uint256_signed_nn(base_array[iter]);
    assert res = 1;
    assert new_array[iter] = res;

    return test_signed_nn(base_array, new_array, iter + 1, last);
}

func test_unsigned_div_rem{range_check_ptr}(
    base_array: Uint256*, new_array: Uint256*, iter: felt, last: felt
) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }

    let (quotient: Uint256, remainder: Uint256) = uint256_unsigned_div_rem(
        base_array[iter], Uint256(7, 8)
    );
    assert new_array[(iter * 2)] = quotient;
    assert new_array[(iter * 2) + 1] = remainder;

    return test_unsigned_div_rem(base_array, new_array, iter + 1, last);
}

func test_split_64{range_check_ptr}(
    base_array: felt*, new_array: felt*, iter: felt, last: felt
) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }

    let (low: felt, high: felt) = split_64(base_array[iter]);
    assert new_array[(iter * 2)] = low;
    assert new_array[(iter * 2) + 1] = high;
    return test_split_64(base_array, new_array, iter + 1, last);
}

func test_integration{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    base_array: Uint256*, new_array: Uint256*, iter: felt, last: felt
) -> () {
    alloc_locals;

    if (iter == last) {
        return ();
    }

    let (add: Uint256, carry_high: felt) = uint256_add(base_array[iter], base_array[iter + 1]);
    let (quotient: Uint256, remainder: Uint256) = uint256_unsigned_div_rem(add, Uint256(5, 3));
    let (low: Uint256, high: Uint256) = uint256_mul(quotient, remainder);
    let (bitwise_or: Uint256) = uint256_or(low, high);
    let (reverse_endian: Uint256) = uint256_reverse_endian(bitwise_or);
    let (result: Uint256) = uint256_sqrt(reverse_endian);

    assert new_array[iter] = result;
    return test_integration(base_array, new_array, iter + 1, last);
}

func run_tests{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(array_len: felt) -> () {
    alloc_locals;
    let (uint256_array: Uint256*) = alloc();
    fill_uint256_array(uint256_array, Uint256(57, 8), Uint256(57, 101), array_len, 0);

    let (array_sqrt: Uint256*) = alloc();
    test_sqrt(uint256_array, array_sqrt, 0, array_len);

    let (array_signed_nn: felt*) = alloc();
    test_signed_nn(uint256_array, array_signed_nn, 0, array_len);

    let (array_unsigned_div_rem: Uint256*) = alloc();
    test_unsigned_div_rem(uint256_array, array_unsigned_div_rem, 0, array_len);

    let (felt_array: felt*) = alloc();
    fill_array(felt_array, 0, 3, 0, array_len);

    let (array_split_64: felt*) = alloc();
    test_split_64(felt_array, array_split_64, 0, array_len);

    let (array_test_integration: Uint256*) = alloc();
    test_integration(uint256_array, array_test_integration, 0, array_len - 1);

    return ();
}

func main{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() {
    run_tests(10);

    return ();
}
