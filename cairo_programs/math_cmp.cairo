%builtins range_check

from starkware.cairo.common.math_cmp import (
    is_not_zero,
    is_nn,
    is_le,
    is_nn_le,
    is_in_range,
    is_le_felt,
)

func main{range_check_ptr: felt}() {
    // is_not_zero
    let a = is_not_zero(10);
    assert a = 1;
    let b = is_not_zero(1);
    assert b = 1;
    let c = is_not_zero(0);
    assert c = 0;

    // is_nn
    let d = is_nn(0);
    assert d = 1;
    let e = is_nn(88);
    assert e = 1;
    let f = is_nn(-88);
    assert f = 0;

    // is_le
    let g = is_le(1, 2);
    assert g = 1;
    let h = is_le(2, 2);
    assert h = 1;
    let i = is_le(56, 20);
    assert i = 0;

    // is_nn_le
    let j = is_nn_le(1, 2);
    assert j = 1;
    let k = is_nn_le(2, 2);
    assert k = 1;
    let l = is_nn_le(56, 20);
    assert l = 0;

    // is_in_range
    let m = is_in_range(1, 2, 3);
    assert m = 0;
    let n = is_in_range(2, 2, 5);
    assert n = 1;
    let o = is_in_range(56, 20, 120);
    assert o = 1;

    // is_le_felt
    let p = is_le_felt(1, 2);
    assert p = 1;
    let q = is_le_felt(2, 2);
    assert q = 1;
    let r = is_le_felt(56, 20);
    assert r = 0;

    return ();
}
