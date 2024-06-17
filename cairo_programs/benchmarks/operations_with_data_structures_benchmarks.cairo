from operations_with_data_structures import run_tests
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func main{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() {
    run_tests(0, 500);
    return ();
}
