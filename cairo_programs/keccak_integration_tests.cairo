%builtins range_check bitwise

from starkware.cairo.common.keccak import unsafe_keccak, unsafe_keccak_finalize, KeccakState
from starkware.cairo.common.cairo_keccak.keccak import cairo_keccak, finalize_keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_uint256
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import unsigned_div_rem

func fill_array(array: felt*, base: felt, step: felt, array_length: felt, iter: felt) {
    if (iter == array_length) {
        return ();
    }
    assert array[iter] = base + step * iter;
    return fill_array(array, base, step, array_length, iter + 1);
}

func test_integration{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}(iter: felt, last: felt) {
    alloc_locals;
    if (iter == last) {
        return ();
    }

    let (data_1: felt*) = alloc();
    let data_len: felt = 15;
    let chunk_len: felt = 5;

    fill_array(data_1, iter, iter + 1, data_len, 0);

    let (low_1: felt, high_1: felt) = unsafe_keccak(data_1, chunk_len);
    let (low_2: felt, high_2: felt) = unsafe_keccak(data_1 + chunk_len, chunk_len);
    let (low_3: felt, high_3: felt) = unsafe_keccak(data_1 + 2 * chunk_len, chunk_len);

    // With the results of unsafe_keccak, create an array to pass to unsafe_keccak_finalize
    // through a KeccakState
    let (data_2: felt*) = alloc();
    assert data_2[0] = low_1;
    assert data_2[1] = high_1;
    assert data_2[2] = low_2;
    assert data_2[3] = high_2;
    assert data_2[4] = low_3;
    assert data_2[5] = high_3;

    let keccak_state: KeccakState = KeccakState(start_ptr=data_2, end_ptr=data_2 + 6);
    let res_1: Uint256 = unsafe_keccak_finalize(keccak_state);

    let (data_3: felt*) = alloc();

    // This is done to make sure that the numbers inserted in data_3
    // fit in a u64
    let (q, r) = unsigned_div_rem(res_1.low, 18446744073709551615);
    assert data_3[0] = q;
    let (q, r) = unsigned_div_rem(res_1.high, 18446744073709551615);
    assert data_3[1] = q;

    let (keccak_ptr: felt*) = alloc();
    let keccak_ptr_start = keccak_ptr;

    let res_2: Uint256 = cairo_keccak{keccak_ptr=keccak_ptr}(data_3, 16);

    finalize_keccak(keccak_ptr_start=keccak_ptr_start, keccak_ptr_end=keccak_ptr);

    let (inputs) = alloc();
    let inputs_start = inputs;
    keccak_add_uint256{inputs=inputs_start}(num=res_2, bigend=0);

    // These values are hardcoded for last = 10
    // Since we are dealing with hash functions and using the output of one of them
    // as the input of the other, asserting only the last results of the iteration
    // should be enough
    if (iter == last - 1 and last == 10) {
        assert res_2.low = 3896836249413878817054429671793519200;
        assert res_2.high = 253424239110447628170109510737834198489;

        assert inputs[0] = 16681956707691293280;
        assert inputs[1] = 211247916371739620;
        assert inputs[2] = 6796127878994642393;
        assert inputs[3] = 13738155530201662906;
    }

    // These values are hardcoded for last = 100
    // This should be used for benchmarking.
    if (iter == last - 1 and last == 100) {
        assert res_2.low = 52798800345724801884797411011515944813;
        assert res_2.high = 159010026777930121161844734347918361509;

        assert inputs[0] = 14656556134934286189;
        assert inputs[1] = 2862228701973161639;
        assert inputs[2] = 206697371206337445;
        assert inputs[3] = 8619950823980503604;
    }

    return test_integration{range_check_ptr=range_check_ptr, bitwise_ptr=bitwise_ptr}(
        iter + 1, last
    );
}

func run_test{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}(last: felt) {
    test_integration(0, last);
    return ();
}

func main{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() {
    run_test(10);
    return ();
}
