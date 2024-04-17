%builtins range_check

from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_write

struct MyStruct {
    a: felt,
    b: felt, 
    c: felt,
}

func main{range_check_ptr: felt}() {
    let name = 0x4b4b5254;
    let (dict_ptr) = default_dict_new(0);
    let pointer_size = 3;

    tempvar one = new MyStruct(1,2,3);
    dict_write{dict_ptr=dict_ptr}(0, cast(one, felt));
    tempvar two = new MyStruct(2,3,4);
    dict_write{dict_ptr=dict_ptr}(1, cast(two, felt));
    tempvar three = new MyStruct(3,4,5);
    dict_write{dict_ptr=dict_ptr}(2, cast(three, felt));
    tempvar four = new MyStruct(4,5,6);
    dict_write{dict_ptr=dict_ptr}(3, cast(four, felt));
    %{
        print(bytes.fromhex(f"{ids.name:062x}").decode().replace('\x00',''))
        data = __dict_manager.get_dict(ids.dict_ptr)
        print(
            {k: v if isinstance(v, int) else [memory[v + i] for i in range(ids.pointer_size)] for k, v in data.items()}
        )
    %}
    return();
}