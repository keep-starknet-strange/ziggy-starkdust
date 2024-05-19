%builtins range_check bitwise
from starkware.cairo.common.math import signed_div_rem, unsigned_div_rem
from starkware.cairo.common.bitwise import bitwise_operations
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.find_element import find_element, search_sorted_lower
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.usort import usort

struct GearRatios {
    crankset: felt,
    cogset: felt,
}

struct Bicycle {
    id: felt,
    basket: felt*,
    gear_ratios: GearRatios,
}

func fill_array{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    arr: felt*, seed: felt, index: felt
) {
    if (index == 5) {
        return ();
    }
    assert arr[index] = seed * index + seed;
    let (val1, val2, val3) = bitwise_operations(seed, arr[index]);
    let (q, new_seed) = unsigned_div_rem((val1 - val2 + val3 + 1000), 1000);
    return fill_array(arr, new_seed, index + 1);
}

func initialize_bike{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    id: felt, crank: felt, cog: felt
) -> (bike: Bicycle) {
    alloc_locals;
    let arr: felt* = alloc();
    fill_array(arr, id, 0);
    let gears = GearRatios(crankset=crank, cogset=cog);
    return (bike=Bicycle(id=id, basket=arr, gear_ratios=gears));
}

func fill_bike_array{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}(
    arr: Bicycle*, len: felt, index: felt
) {
    alloc_locals;
    if (index == len) {
        return ();
    }

    let (q, crank) = signed_div_rem(index + 1, 3, 30);
    let (q, cog) = signed_div_rem(index + 2, 7, 30);
    let (bike) = initialize_bike(index, crank, cog);

    assert arr[index] = bike;
    return fill_bike_array(arr, len, index + 1);
}

func assert_find_element(element_ptr: Bicycle*) {
    assert element_ptr.gear_ratios.crankset = 0;
    assert element_ptr.gear_ratios.cogset = 3;
    assert element_ptr.basket[0] = 29;
    assert element_ptr.basket[1] = 116;
    assert element_ptr.basket[2] = 288;
    assert element_ptr.basket[3] = 256;
    assert element_ptr.basket[4] = 0;
    return ();
}

func assert_sorting(sorted_basket: felt*) {
    assert sorted_basket[0] = 0;
    assert sorted_basket[1] = 29;
    assert sorted_basket[2] = 116;
    assert sorted_basket[3] = 256;
    assert sorted_basket[4] = 288;
    return ();
}

func run_tests{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}(iter: felt, stop: felt) {
    alloc_locals;
    if (iter == stop) {
        return ();
    }

    let bike_arr: Bicycle* = alloc();
    fill_bike_array(bike_arr, 30, 0);
    let (element_ptr: Bicycle*) = find_element(
        array_ptr=bike_arr, elm_size=Bicycle.SIZE, n_elms=30, key=29
    );

    assert_find_element(element_ptr);

    let (basket_len, sorted_basket, multiplicities) = usort(5, element_ptr.basket);
    assert_sorting(sorted_basket);

    let bike_small_array: Bicycle* = alloc();
    assert bike_small_array[0] = bike_arr[0];
    assert bike_small_array[1] = bike_arr[5];
    assert bike_small_array[2] = bike_arr[10];
    assert bike_small_array[3] = bike_arr[15];
    assert bike_small_array[4] = bike_arr[20];

    let (elem_ptr_lower: Bicycle*) = search_sorted_lower(
        array_ptr=bike_small_array, elm_size=Bicycle.SIZE, n_elms=30, key=6
    );

    assert elem_ptr_lower.id = 10;

    return run_tests(iter + 1, stop);
}

func main{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;
    run_tests(0, 10);

    return ();
}
