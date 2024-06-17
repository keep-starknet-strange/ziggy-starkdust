%builtins range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.cairo_keccak.keccak import _finalize_keccak_inner, cairo_keccak, BLOCK_SIZE, KECCAK_STATE_SIZE_FELTS
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.uint256 import Uint256

// Verifies that the results of cairo_keccak() are valid. For optimization, this can be called only
// once after all the keccak calculations are completed.
// Version copied from starknet/security/whitelists/cairo_keccak.json
func finalize_keccak{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    keccak_ptr_start: felt*, keccak_ptr_end: felt*
) {
    alloc_locals;

    tempvar n = (keccak_ptr_end - keccak_ptr_start) / (2 * KECCAK_STATE_SIZE_FELTS);
    if (n == 0) {
        return ();
    }

    %{
        # Add dummy pairs of input and output.
        _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
        _block_size = int(ids.BLOCK_SIZE)
        assert 0 <= _keccak_state_size_felts < 100
        assert 0 <= _block_size < 1000
        inp = [0] * _keccak_state_size_felts
        padding = (inp + keccak_func(inp)) * _block_size
        segments.write_arg(ids.keccak_ptr_end, padding)
    %}

    // Compute the amount of blocks (rounded up).
    let (local q, r) = unsigned_div_rem(n + BLOCK_SIZE - 1, BLOCK_SIZE);
    _finalize_keccak_inner(keccak_ptr_start, n=q);
    return ();
}

func main{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;

    let (keccak_ptr: felt*) = alloc();
    let keccak_ptr_start = keccak_ptr;

    let (inputs: felt*) = alloc();

    assert inputs[0] = 8031924123371070792;
    assert inputs[1] = 560229490;

    let n_bytes = 16;

    let (res: Uint256) = cairo_keccak{keccak_ptr=keccak_ptr}(inputs=inputs, n_bytes=n_bytes);

    assert res.low = 293431514620200399776069983710520819074;
    assert res.high = 317109767021952548743448767588473366791;

    finalize_keccak(keccak_ptr_start=keccak_ptr_start, keccak_ptr_end=keccak_ptr);

    return ();
}
