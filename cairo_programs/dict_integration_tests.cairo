%builtins range_check

from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.dict import dict_read, dict_write, dict_update, dict_squash

func fill_dictionary{dict_start: DictAccess*}(base: felt, step: felt, iter: felt, last: felt) {
    alloc_locals;
    if (iter == last) {
        return ();
    }

    let new_val: felt = base + step * iter;

    dict_write{dict_ptr=dict_start}(key=iter, new_value=new_val);
    let (local val: felt) = dict_read{dict_ptr=dict_start}(key=iter);
    assert val = new_val;

    return fill_dictionary{dict_start=dict_start}(base, step, iter + 1, last);
}

func update_dictionary{dict_start: DictAccess*}(base: felt, step: felt, iter: felt, last: felt) {
    alloc_locals;
    if (iter == last) {
        return ();
    }

    let (local prev_val: felt) = dict_read{dict_ptr=dict_start}(key=iter);
    let new_val: felt = base + step * iter;

    dict_update{dict_ptr=dict_start}(key=iter, prev_value=prev_val, new_value=new_val);
    let (local val: felt) = dict_read{dict_ptr=dict_start}(key=iter);
    assert val = new_val;

    return update_dictionary{dict_start=dict_start}(base, step, iter + 1, last);
}

func check_squashed_dictionary{dict_end: DictAccess*}(
    iter: felt, last: felt, init_base: felt, init_step: felt, final_base: felt, final_step: felt
) {
    alloc_locals;
    if (iter == last) {
        return ();
    }

    let prev_val: felt = init_base + init_step * iter;
    let new_val: felt = final_base + final_step * iter;

    assert dict_end[iter] = DictAccess(key=iter, prev_value=prev_val, new_value=new_val);

    let a = dict_end[iter];
    let hola = a.prev_value;
    let chau = a.new_value;

    return check_squashed_dictionary{dict_end=dict_end}(
        iter + 1, last, init_base, init_step, final_base, final_step
    );
}

func test_integration{range_check_ptr: felt}(iter: felt, last: felt) -> () {
    alloc_locals;
    if (iter == last) {
        return ();
    }

    let init_base = 1;
    let init_step = 2;

    let final_base = 2;
    let final_step = 3;

    let (local dict_start: DictAccess*) = default_dict_new(9998789);
    let dict_end = dict_start;

    fill_dictionary{dict_start=dict_end}(base=init_base, step=init_step, iter=0, last=last);
    update_dictionary{dict_start=dict_end}(base=final_base, step=final_step, iter=0, last=last);

    let (squashed_dict_start, squashed_dict_end) = dict_squash(dict_start, dict_end);
    check_squashed_dictionary{dict_end=squashed_dict_end}(
        iter=0,
        last=last,
        init_base=init_base,
        init_step=init_step,
        final_base=final_base,
        final_step=final_step,
    );

    return test_integration(iter + 1, last);
}

func run_tests{range_check_ptr}(last: felt) {
    test_integration(0, last);

    return ();
}

func main{range_check_ptr: felt}() {
    run_tests(10);

    return ();
}
