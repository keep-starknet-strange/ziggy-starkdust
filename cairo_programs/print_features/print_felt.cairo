%builtins range_check

func main{range_check_ptr: felt}() {
    let x = 123;
    %{
        print(ids.x)
    %}
    return();
}
