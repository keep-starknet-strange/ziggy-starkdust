from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict import dict_write, dict_read

struct Structure {
    a: felt,
    b: felt,
    c: felt,
}

func main() {
    // Create dictionary
    let (dictionary: DictAccess*) = default_dict_new(default_value=0);
    // Create & initialize struct_pointer
    let (struct_ptr: Structure*) = alloc();
    assert struct_ptr[0] = Structure(1, 2, 3);
    // Cast ptr to felt and store it in the dictionary
    tempvar struct_ptr_cast_felt = cast(struct_ptr, felt);
    dict_write{dict_ptr=dictionary}(key=0, new_value=struct_ptr_cast_felt);
    // Read the casted ptr from the dictionary and compare it to the one we stored
    let read_struct_ptr_cast_felt: felt = dict_read{dict_ptr=dictionary}(key=0);
    assert struct_ptr_cast_felt = read_struct_ptr_cast_felt;
    // Cast he ptr back to Structure* and check its value
    let read_struct_ptr_cast_struct_ptr = cast(read_struct_ptr_cast_felt, Structure*);
    assert struct_ptr = read_struct_ptr_cast_struct_ptr;
    // Confirm that the ptr still leads to the data we initialized
    assert read_struct_ptr_cast_struct_ptr[0].a = 1;
    assert read_struct_ptr_cast_struct_ptr[0].b = 2;
    assert read_struct_ptr_cast_struct_ptr[0].c = 3;
    // Now we do the same, but we read the struct_ptr from the dictionary as a Struct*
    // without an explicit cast
    let read_struct_ptr: Structure* = dict_read{dict_ptr=dictionary}(key=0);
    assert struct_ptr = read_struct_ptr;
    // Confirm that the ptr still leads to the data we initialized
    assert read_struct_ptr[0].a = 1;
    assert read_struct_ptr[0].b = 2;
    assert read_struct_ptr[0].c = 3;
    return ();
}
