%builtins poseidon
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.builtin_poseidon.poseidon import (
    poseidon_hash,
    poseidon_hash_single,
    poseidon_hash_many,
)
from starkware.cairo.common.alloc import alloc

func construct_array(base: felt, step: felt, length: felt) -> felt* {
    alloc_locals;
    let array: felt* = alloc();
    fill_array(base, step, length, 0, array);
    return array;
}

func fill_array(base: felt, step: felt, length: felt, acc: felt, array: felt*) {
    alloc_locals;
    if (acc == length) {
        return ();
    }
    assert array[acc] = base + acc * step;
    return fill_array(base, step, length, acc + 1, array);
}

func compute_poseidon_single{poseidon_ptr: PoseidonBuiltin*}(
    array: felt*, length: felt, acc: felt
) {
    if (acc == length) {
        return ();
    }
    let (r) = poseidon_hash_single(array[acc]);
    return compute_poseidon_single(array, length, acc + 1);
}

func compute_poseidon_double{poseidon_ptr: PoseidonBuiltin*}(
    array: felt*, length: felt, acc: felt
) {
    if (acc == length) {
        return ();
    }
    let (r) = poseidon_hash(array[acc], array[acc + 1]);
    return compute_poseidon_double(array, length, acc + 2);
}

func compute_poseidon_triple{poseidon_ptr: PoseidonBuiltin*}(
    array: felt*, length: felt, acc: felt
) {
    if (acc == length) {
        return ();
    }
    let sub_array: felt* = alloc();
    assert sub_array[0] = array[acc];
    assert sub_array[1] = array[acc + 1];
    assert sub_array[2] = array[acc + 2];
    let (r) = poseidon_hash_many(3, sub_array);
    return compute_poseidon_triple(array, length, acc + 3);
}

func run_test{poseidon_ptr: PoseidonBuiltin*}(n: felt) {
    alloc_locals;
    let base = 218676008889449692916464780911713710628115973574242889792891157041292792362;
    let step = 23589912357;
    let single_length = n;
    let double_length = n * 2;
    let triple_length = n * 3;
    let single_array = construct_array(step, base, single_length);
    let double_array = construct_array(base, step, double_length);
    let triple_array = construct_array(base, step, triple_length);
    compute_poseidon_single(single_array, single_length, 0);
    compute_poseidon_double(double_array, double_length, 0);
    compute_poseidon_triple(triple_array, triple_length, 0);
    return ();
}

func main{poseidon_ptr: PoseidonBuiltin*}() {
    run_test(10);
    return ();
}
