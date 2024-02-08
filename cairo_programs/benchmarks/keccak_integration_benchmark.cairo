from keccak_integration_tests import run_test
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func main{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() -> () {
    run_test(300);
    return ();
}
