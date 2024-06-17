from dict_integration_tests import run_tests

func main{range_check_ptr: felt}() {
    run_tests(200);

    return ();
}
