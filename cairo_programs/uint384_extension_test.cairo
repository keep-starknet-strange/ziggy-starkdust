%builtins range_check

from cairo_programs.uint384_extension import u384_ext, Uint768, Uint384

func test_uint384_extension_operations{range_check_ptr}() {
    // Test unsigned_div_rem_uint768_by_uint384
    let a = Uint768(1, 2, 3, 4, 5, 6);
    let div = Uint384(6, 7, 8);
    let (q, r) = u384_ext.unsigned_div_rem_uint768_by_uint384(a, div);
    assert q.d0 = 328319314958874220607240343889245110272;
    assert q.d1 = 329648542954659136480144150949525454847;
    assert q.d2 = 255211775190703847597530955573826158591;
    assert q.d3 = 0;
    assert q.d4 = 0;
    assert q.d5 = 0;

    assert r.d0 = 71778311772385457136805581255138607105;
    assert r.d1 = 147544307532125661892322583691118247938;
    assert r.d2 = 3;
    return ();
}

func test_uint384_unsigned_div_rem_alt{range_check_ptr}() {
    // Test unsigned_div_rem_uint768_by_uint384
    let a = Uint768(1, 2, 3, 4, 5, 6);
    let div = Uint384(6, 7, 8);
    let (q, r) = u384_ext.unsigned_div_rem_uint768_by_uint384_alt(a, div);
    assert q.d0 = 328319314958874220607240343889245110272;
    assert q.d1 = 329648542954659136480144150949525454847;
    assert q.d2 = 255211775190703847597530955573826158591;
    assert q.d3 = 0;
    assert q.d4 = 0;
    assert q.d5 = 0;

    assert r.d0 = 71778311772385457136805581255138607105;
    assert r.d1 = 147544307532125661892322583691118247938;
    assert r.d2 = 3;
    return ();
}

func main{range_check_ptr: felt}() {
    test_uint384_extension_operations();
    test_uint384_unsigned_div_rem_alt();
    return ();
}
