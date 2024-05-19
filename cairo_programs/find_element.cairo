%builtins range_check
from starkware.cairo.common.find_element import find_element
from starkware.cairo.common.alloc import alloc

struct MyStruct {
    a: felt,
    b: felt,
}

func main{range_check_ptr}() -> () {
    // Create an array with MyStruct elements (1,2), (3,4), (5,6).
    alloc_locals;
    let (local array_ptr: MyStruct*) = alloc();
    assert array_ptr[0] = MyStruct(a=1, b=2);
    assert array_ptr[1] = MyStruct(a=3, b=4);
    assert array_ptr[2] = MyStruct(a=5, b=6);

    // Find any element with key '5'.
    let (element_ptr: MyStruct*) = find_element(
        array_ptr=array_ptr, elm_size=MyStruct.SIZE, n_elms=3, key=5
    );
    // A pointer to the element with index 2 is returned.
    assert element_ptr.a = 5;
    assert element_ptr.b = 6;

    return ();
}
