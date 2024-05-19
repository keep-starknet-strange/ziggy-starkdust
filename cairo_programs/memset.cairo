from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memset import memset
from starkware.cairo.common.bool import TRUE, FALSE

func check_array(array: felt*, value: felt, array_length: felt, iterator: felt) -> (r: felt) {
    if (iterator == array_length) {
        return (TRUE,);
    }
    if (array[iterator] != value) {
        return (FALSE,);
    }
    return check_array(array, value, array_length, iterator + 1);
}

func main() {
    alloc_locals;
    let (local strings: felt*) = alloc();
    memset(strings, 'Lambda', 20);
    let check_string: felt = check_array(strings, 'Lambda', 20, 0);
    assert check_string = TRUE;
    assert strings[20] = 'can insert new value';

    let numbers: felt* = alloc();
    memset(numbers, 10, 100);
    let check_string: felt = check_array(numbers, 10, 100, 0);
    assert check_string = TRUE;
    assert numbers[100] = 11;

    return ();
}
