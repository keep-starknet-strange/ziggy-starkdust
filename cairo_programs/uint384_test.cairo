%builtins range_check

from cairo_programs.uint384 import u384, Uint384, Uint384_expand

func test_uint384_operations{range_check_ptr}() {
    // Test unsigned_div_rem
    let a = Uint384(83434123481193248, 82349321849739284, 839243219401320423);
    let div = Uint384(9283430921839492319493, 313248123482483248, 3790328402913840);
    let (quotient: Uint384, remainder: Uint384) = u384.unsigned_div_rem{
        range_check_ptr=range_check_ptr
    }(a, div);
    assert quotient.d0 = 221;
    assert quotient.d1 = 0;
    assert quotient.d2 = 0;

    assert remainder.d0 = 340282366920936411825224315027446796751;
    assert remainder.d1 = 340282366920938463394229121463989152931;
    assert remainder.d2 = 1580642357361782;

    // Test split_128
    let b = 6805647338418769269267492148635364229100;
    let (low, high) = u384.split_128{range_check_ptr=range_check_ptr}(b);
    assert high = 19;
    assert low = 340282366920938463463374607431768211436;

    // Test _add_no_uint384_test

    let c = Uint384(3789423292314891293, 21894, 340282366920938463463374607431768211455);
    let d = Uint384(32838232, 17, 8);
    let (sum_res, carry) = u384._add_no_uint384_check(c, d);

    assert sum_res.d0 = 3789423292347729525;
    assert sum_res.d1 = 21911;
    assert sum_res.d2 = 7;
    assert carry = 1;

    // Test sqrt
    let f = Uint384(83434123481193248, 82349321849739284, 839243219401320423);
    let (root) = u384.sqrt(f);
    assert root.d0 = 100835122758113432298839930225328621183;
    assert root.d1 = 916102188;
    assert root.d2 = 0;

    let g = Uint384(1, 1, 1);
    let (sign_g) = u384.signed_nn(g);
    assert sign_g = 1;

    let h = Uint384(0, 0, 170141183460469231731687303715884105729);
    let (sign_h) = u384.signed_nn(h);
    assert sign_h = 0;

    return();
}

func main{range_check_ptr: felt}() {
    test_uint384_operations();
    return ();
}
