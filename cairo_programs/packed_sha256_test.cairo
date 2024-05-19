%builtins range_check bitwise
from starkware.cairo.common.alloc import alloc
from cairo_programs.packed_sha256 import (
    BLOCK_SIZE,
    compute_message_schedule,
    sha2_compress,
    get_round_constants,
    sha256,
    finalize_sha256,
)
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func test_packed_sha256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;
    let input_len = 3;
    let input: felt* = alloc();
    assert input[0] = 1214606444;
    assert input[1] = 1864398703;
    assert input[2] = 1919706112;
    let n_bytes = 11;

    let (local sha256_ptr_start: felt*) = alloc();
    let sha256_ptr = sha256_ptr_start;

    let (local output: felt*) = sha256{sha256_ptr=sha256_ptr}(input, n_bytes);
    assert output[0] = 1693223114;
    assert output[1] = 11692261;
    assert output[2] = 3122279783;
    assert output[3] = 2317046550;
    assert output[4] = 3524457715;
    assert output[5] = 1722959730;
    assert output[6] = 844319370;
    assert output[7] = 3970137916;

    finalize_sha256(sha256_ptr_start=sha256_ptr_start, sha256_ptr_end=sha256_ptr);

    return ();
}

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    test_packed_sha256();
    return ();
}
