%builtins range_check

from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_write

func main{range_check_ptr: felt}() {
    let name = 0x4b4b5254;
    let (dict_ptr) = default_dict_new(0);
    let pointer_size = 1;
    dict_write{dict_ptr=dict_ptr}(0, 1);
    dict_write{dict_ptr=dict_ptr}(1, 2);
    dict_write{dict_ptr=dict_ptr}(2, 3);
    dict_write{dict_ptr=dict_ptr}(3, 4);
    dict_write{dict_ptr=dict_ptr}(4, 5);
    %{
        print(bytes.fromhex(f"{ids.name:062x}").decode().replace('\x00',''))
        data = __dict_manager.get_dict(ids.dict_ptr)
        print(
            {k: v if isinstance(v, int) else [memory[v + i] for i in range(ids.pointer_size)] for k, v in data.items()}
        )
    %}
    return();
}