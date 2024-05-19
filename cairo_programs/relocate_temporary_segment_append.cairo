from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.segments import relocate_segment

func main() {
    alloc_locals;
    // Create temporary_array in a temporary segment
    local temporary_array: felt*;
    %{ ids.temporary_array = segments.add_temp_segment() %}

    // Insert values into temporary_array
    assert temporary_array[0] = 4;
    assert temporary_array[1] = 5;
    assert temporary_array[2] = 6;

    // Create array
    let (array: felt*) = alloc();
    assert array[0] = 1;
    assert array[1] = 2;
    assert array[2] = 3;

    // Realocate temporary_array into the array segment
    relocate_segment(src_ptr=temporary_array, dest_ptr=array + 3);

    return ();
}
