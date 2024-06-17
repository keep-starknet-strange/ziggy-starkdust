from blake2s_integration_tests import run_tests
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    run_tests(300);

    return ();
}
