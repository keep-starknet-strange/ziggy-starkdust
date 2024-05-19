from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.memset import memset

// Helper functions
func fill_array(array: felt*, base: felt, step: felt, array_length: felt, iterator: felt) {
    if (iterator == array_length) {
        return ();
    }
    assert array[iterator] = base + step * iterator;
    return fill_array(array, base, step, array_length, iterator + 1);
}

func check_array(array: felt*, value: felt, array_length: felt, iterator: felt) -> (r: felt) {
    if (iterator == array_length) {
        return (TRUE,);
    }
    if (array[iterator] != value) {
        return (FALSE,);
    }
    return check_array(array, value, array_length, iterator + 1);
}

func compare_arrays(array_a: felt*, array_b: felt*, array_length: felt, iterator: felt) -> (
    r: felt
) {
    if (iterator == array_length) {
        return (TRUE,);
    }
    if (array_a[iterator] != array_b[iterator]) {
        return (FALSE,);
    }
    return compare_arrays(array_a, array_b, array_length, iterator + 1);
}

// ---------------------------------------------------------------------------------- #

// Test functions
func test_memcpy_different_segments(src: felt*, len: felt, iter: felt) -> () {
    alloc_locals;
    if (iter == len) {
        return ();
    }

    let (dst: felt*) = alloc();
    memcpy(dst=dst, src=src, len=len);

    let result: felt = compare_arrays(src, dst, len, 0);
    assert result = TRUE;

    return test_memcpy_different_segments(src, len, iter + 1);
}

func test_memcpy_same_segment(src: felt*, dst: felt*, len: felt, iter: felt) -> () {
    alloc_locals;
    if (iter == len) {
        return ();
    }

    let new_dst: felt* = dst + len * iter;
    memcpy(dst=new_dst, src=src, len=len);

    let result: felt = compare_arrays(src, new_dst, len, 0);
    assert result = TRUE;

    return test_memcpy_same_segment(src, dst, len, iter + 1);
}

func test_memset_different_segments(n: felt, iter: felt) -> () {
    alloc_locals;
    if (iter == n) {
        return ();
    }

    let (dst: felt*) = alloc();
    memset(dst=dst, value=1234, n=n);

    let result: felt = check_array(dst, 1234, n, 0);
    assert result = TRUE;

    return test_memset_different_segments(n, iter + 1);
}

func test_memset_same_segment(dst: felt*, n: felt, iter: felt) -> () {
    alloc_locals;
    if (iter == n) {
        return ();
    }

    let new_dst: felt* = dst + n * iter;
    memset(dst=new_dst, value=1234, n=n);

    let result: felt = check_array(new_dst, 1234, n, 0);
    assert result = TRUE;

    return test_memset_same_segment(dst, n, iter + 1);
}

func test_integration(src: felt*, len: felt, n: felt, iter: felt) -> () {
    alloc_locals;
    if (iter == len) {
        return ();
    }

    let (initial_dst: felt*) = alloc();
    memcpy(dst=initial_dst, src=src, len=len);
    let res_1: felt = compare_arrays(src, initial_dst, len, 0);
    assert res_1 = TRUE;

    let (dst: felt*) = alloc();
    memset(dst=dst, value=initial_dst[iter], n=n);
    let res_2: felt = check_array(dst, initial_dst[iter], n, 0);
    assert res_2 = TRUE;

    let (final_dst: felt*) = alloc();
    memcpy(dst=final_dst, src=dst, len=n);
    let res_3: felt = check_array(final_dst, initial_dst[iter], n, 0);
    assert res_3 = TRUE;

    return test_integration(src, len, n, iter + 1);
}

func run_tests(len: felt, n: felt) -> () {
    alloc_locals;

    let (array: felt*) = alloc();
    fill_array(array, 7, 3, len, 0);

    test_memcpy_different_segments(array, len, 0);

    let (dst_1: felt*) = alloc();
    test_memcpy_same_segment(array, dst_1, len, 0);

    test_memset_different_segments(n, 0);

    let (dst_2: felt*) = alloc();
    test_memset_same_segment(dst_2, n, 0);

    test_integration(array, len, n, 0);

    return ();
}

func main() {
    run_tests(10, 10);
    return ();
}
