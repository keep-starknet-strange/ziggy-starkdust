%builtins output pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2

func main{output_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    let (seed) = hash2{hash_ptr=pedersen_ptr}(0, 0);
    assert [output_ptr] = seed;
    let output_ptr = output_ptr + 1;
    return ();
}
