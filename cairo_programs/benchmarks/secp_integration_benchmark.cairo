from secp_integration_tests import run_tests

func main{range_check_ptr}() {
    run_tests(0, 10);
    return ();
}
