%builtins pedersen

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2

func get_hash(hash_ptr: HashBuiltin*, num_a: felt, num_b: felt) -> (
    hash_ptr: HashBuiltin*, r: felt
) {
    with hash_ptr {
        let (result) = hash2(num_a, num_b);
    }
    return (hash_ptr=hash_ptr, r=result);
}

func builtins_wrapper{
    pedersen_ptr: HashBuiltin*,
}(num_a: felt, num_b: felt) {
    let (pedersen_ptr, result: felt) = get_hash(pedersen_ptr, num_a, num_b);

    return ();
}

func builtins_wrapper_iter{
    pedersen_ptr: HashBuiltin*,
}(num_a: felt, num_b: felt, n_iterations: felt) {
    builtins_wrapper(num_a, num_b);
    if (n_iterations != 0) {
        builtins_wrapper_iter(num_a, num_b, n_iterations - 1);
        tempvar pedersen_ptr = pedersen_ptr;
    } else {
        tempvar pedersen_ptr = pedersen_ptr;
    }

    return ();
}

func main{
    pedersen_ptr: HashBuiltin*,
}() {
    let num_a = 123568;
    let num_b = 5673940;
    builtins_wrapper_iter(num_a, num_b, 50000);

    return ();
}
