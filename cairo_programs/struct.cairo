struct MyStruct {
    first_member: felt,
    second_member: felt,
}

func main() {
    let struct_instance = MyStruct(first_member=1, second_member=2);
    let struct_instance_2 = MyStruct(3, 4);
    return ();
}
