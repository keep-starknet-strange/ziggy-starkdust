%builtins range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_blake2s.blake2s import blake2s, _finalize_blake2s_inner, _get_sigma, INSTANCE_SIZE, INPUT_BLOCK_FELTS
from starkware.cairo.common.cairo_blake2s.packed_blake2s import N_PACKED_INSTANCES, blake2s_compress
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.math import assert_nn_le, split_felt, unsigned_div_rem

const BLAKE2S_INPUT_CHUNK_SIZE_FELTS = INPUT_BLOCK_FELTS;

// Verifies that the results of blake2s() are valid.
func finalize_blake2s{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    blake2s_ptr_start: felt*, blake2s_ptr_end: felt*
) {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();

    let (sigma) = _get_sigma();

    tempvar n = (blake2s_ptr_end - blake2s_ptr_start) / INSTANCE_SIZE;
    if (n == 0) {
        return ();
    }

    %{
        # Add dummy pairs of input and output.
        from starkware.cairo.common.cairo_blake2s.blake2s_utils import IV, blake2s_compress

        _n_packed_instances = int(ids.N_PACKED_INSTANCES)
        assert 0 <= _n_packed_instances < 20
        _blake2s_input_chunk_size_felts = int(ids.BLAKE2S_INPUT_CHUNK_SIZE_FELTS)
        assert 0 <= _blake2s_input_chunk_size_felts < 100

        message = [0] * _blake2s_input_chunk_size_felts
        modified_iv = [IV[0] ^ 0x01010020] + IV[1:]
        output = blake2s_compress(
            message=message,
            h=modified_iv,
            t0=0,
            t1=0,
            f0=0xffffffff,
            f1=0,
        )
        padding = (modified_iv + message + [0, 0xffffffff] + output) * (_n_packed_instances - 1)
        segments.write_arg(ids.blake2s_ptr_end, padding)
    %}

    // Compute the amount of chunks (rounded up).
    let (local n_chunks, _) = unsigned_div_rem(n + N_PACKED_INSTANCES - 1, N_PACKED_INSTANCES);
    let blake2s_ptr = blake2s_ptr_start;
    _finalize_blake2s_inner{blake2s_ptr=blake2s_ptr}(n=n_chunks, sigma=sigma);
    return ();
}

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
