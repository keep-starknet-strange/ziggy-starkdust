%builtins range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_blake2s.blake2s import blake2s, finalize_blake2s
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;
    let inputs: felt* = alloc();
    assert inputs[0] = 'Hell';
    assert inputs[1] = 'o Wo';
    assert inputs[2] = 'rld';
    let (local blake2s_ptr_start) = alloc();
    let blake2s_ptr = blake2s_ptr_start;
    let (output) = blake2s{range_check_ptr=range_check_ptr, blake2s_ptr=blake2s_ptr}(inputs, 9);
    finalize_blake2s(blake2s_ptr_start, blake2s_ptr);
    return ();
}
