%builtins range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_blake2s.blake2s import blake2s, finalize_blake2s, blake2s_felts
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.bool import TRUE

func fill_array(array: felt*, base: felt, step: felt, array_length: felt, iterator: felt) {
    if (iterator == array_length) {
        return ();
    }
    assert array[iterator] = base + step * iterator;
    return fill_array(array, base, step, array_length, iterator + 1);
}

func test_integration{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(iter: felt, last: felt) {
    alloc_locals;
    if (iter == last) {
        return ();
    }

    let (data: felt*) = alloc();
    fill_array(data, iter, 2 * iter, 10, 0);

    let (local blake2s_ptr_start) = alloc();
    let blake2s_ptr = blake2s_ptr_start;
    let (res_1: Uint256) = blake2s{range_check_ptr=range_check_ptr, blake2s_ptr=blake2s_ptr}(
        data, 9
    );

    finalize_blake2s(blake2s_ptr_start, blake2s_ptr);

    let (local blake2s_ptr_start) = alloc();
    let blake2s_ptr = blake2s_ptr_start;

    let (data_2: felt*) = alloc();
    assert data_2[0] = res_1.low;
    assert data_2[1] = res_1.high;

    let (res_2) = blake2s_felts{range_check_ptr=range_check_ptr, blake2s_ptr=blake2s_ptr}(
        2, data_2, TRUE
    );

    finalize_blake2s(blake2s_ptr_start, blake2s_ptr);

    if (iter == last - 1 and last == 10) {
        assert res_1.low = 327684140823325841083166505949840946643;
        assert res_1.high = 28077572547397067729112288485703133566;
        assert res_2.low = 323710308182296053867309835081443411626;
        assert res_2.high = 159988406782415793602959692147600111481;
    }

    if (iter == last - 1 and last == 100) {
        assert res_1.low = 26473789897582596397897414631405692327;
        assert res_1.high = 35314462001555260569814614879256292984;
        assert res_2.low = 256911263205530722270005922452382996929;
        assert res_2.high = 248798531786594770765531047659644061441;
    }

    return test_integration(iter + 1, last);
}

func run_tests{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(last: felt) {
    alloc_locals;
    test_integration(0, last);

    return ();
}

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    run_tests(10);

    return ();
}
