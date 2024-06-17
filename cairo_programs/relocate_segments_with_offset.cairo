from starkware.cairo.common.segments import relocate_segment
from starkware.cairo.common.alloc import alloc

func main() {
    alloc_locals;
    // Create temporary_array_no_offset in a temporary segment
    local temporary_array: felt*;

    %{ ids.temporary_array = segments.add_temp_segment() %}

    // Create array
    let (array: felt*) = alloc();

    // Insert values into array
    assert array[5] = 5;
    assert array[6] = 6;

    // Realocate temporary_array into the array pointer + 5
    relocate_segment(src_ptr=temporary_array, dest_ptr=(array + 5));

    // Assert that the relocated temporary_array gets their values from the array segment
    assert temporary_array[0] = 5;
    assert temporary_array[1] = 6;

    return ();
}
