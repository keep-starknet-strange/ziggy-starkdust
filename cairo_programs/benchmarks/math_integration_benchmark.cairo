from math_integration_tests import run_tests

func repeat{range_check_ptr}(n) -> () {
    if (n == 0) {
        return ();
    }
    run_tests(1000);
    return repeat(n - 1);
}

func main{range_check_ptr}() -> () {
    //FIXME: there seems to be a bug that causes failures for bigger values.
    //For now just run these several times instead.
    repeat(8);
    return ();
}
