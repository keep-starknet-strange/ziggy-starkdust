from poseidon_multirun import run_test
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin

func main{poseidon_ptr: PoseidonBuiltin*}() -> () {
    // For each test, 3 poseidon hashes are computed (single, 2 values, and 3 values)
    run_test(10000);
    return ();
}
