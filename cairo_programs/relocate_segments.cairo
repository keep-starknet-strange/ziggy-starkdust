from starkware.cairo.common.segments import relocate_segment
from starkware.cairo.common.alloc import alloc

func main() {
    alloc_locals;
    // Create temporary_array in a temporary segment
    local temporary_array: felt*;
    %{ ids.temporary_array = segments.add_temp_segment() %}

    // Create array
    let (array: felt*) = alloc();

    // Insert values into array;
    assert array[0] = 50;
    assert array[1] = 51;

    // Realocate temporary_array into the array segment
    relocate_segment(src_ptr=temporary_array, dest_ptr=array);

    // Assert that the realocated temporary_array gets their values from the array segment
    assert temporary_array[0] = 50;
    assert temporary_array[1] = 51;
    assert array[2] = 52;
    assert temporary_array[2] = 52;

    return ();
}
