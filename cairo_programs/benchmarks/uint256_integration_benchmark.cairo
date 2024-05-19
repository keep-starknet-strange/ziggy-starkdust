from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from uint256_integration_tests import run_tests

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() -> () {
    run_tests(4000);
    return ();
}
