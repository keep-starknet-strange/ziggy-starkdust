%builtins range_check
from starkware.cairo.common.math import assert_le_felt

func main{range_check_ptr: felt}() {
    assert_le_felt(1, 2);
    return ();
}
