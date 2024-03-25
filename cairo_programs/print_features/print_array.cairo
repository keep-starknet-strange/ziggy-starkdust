%builtins range_check

from starkware.cairo.common.alloc import alloc

func main{range_check_ptr: felt}() {
    let name = 0x4b4b5254;
    let (arr: felt*) = alloc();
    assert arr[0] = 1;
    assert arr[1] = 2;
    assert arr[2] = 3;
    assert arr[3] = 4;
    assert arr[4] = 5;
    let arr_len = 5;
    %{
        print(bytes.fromhex(f"{ids.name:062x}").decode().replace('\x00',''))
        arr = [memory[ids.arr + i] for i in range(ids.arr_len)]
        print(arr)
    %}
    return();
}