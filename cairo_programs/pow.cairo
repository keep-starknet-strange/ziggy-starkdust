%builtins range_check

from starkware.cairo.common.pow import pow
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.registers import get_ap, get_fp_and_pc

// Returns base ** exp, for 0 <= exp < 2**251.
func pow_manual_implementation{range_check_ptr}(base, exp) -> (res: felt) {
    struct LoopLocals {
        bit: felt,
        temp0: felt,

        res: felt,
        base: felt,
        exp: felt,
    }

    if (exp == 0) {
        return (1,);
    }

    let initial_locs: LoopLocals* = cast(fp - 2, LoopLocals*);
    initial_locs.res = 1, ap++;
    initial_locs.base = base, ap++;
    initial_locs.exp = exp, ap++;

    loop:
    let prev_locs: LoopLocals* = cast(ap - LoopLocals.SIZE, LoopLocals*);
    let locs: LoopLocals* = cast(ap, LoopLocals*);
    locs.base = prev_locs.base * prev_locs.base, ap++;
    %{ ids.locs.bit = (ids.prev_locs.exp % PRIME) & 1 %}
    jmp odd if locs.bit != 0, ap++;

    even:
    locs.exp = prev_locs.exp / 2, ap++;
    locs.res = prev_locs.res, ap++;
    // exp cannot be 0 here.
    static_assert ap + 1 == locs + LoopLocals.SIZE;
    jmp loop, ap++;

    odd:
    locs.temp0 = prev_locs.exp - 1;
    locs.exp = locs.temp0 / 2, ap++;
    locs.res = prev_locs.res * prev_locs.base, ap++;
    static_assert ap + 1 == locs + LoopLocals.SIZE;
    jmp loop if locs.exp != 0, ap++;

    // Cap the number of steps.
    let (__ap__) = get_ap();
    let (__fp__, _) = get_fp_and_pc();
    let n_steps = (__ap__ - cast(initial_locs, felt*)) / LoopLocals.SIZE - 1;
    assert_le(n_steps, 251);
    return (res=locs.res);
}

func main{range_check_ptr: felt}() {
    let (x) = pow(2, 3);
    assert x = 8;
    let (y) = pow(10, 6);
    assert y = 1000000;
    let (z) = pow(152, 25);
    assert z = 3516330588649452857943715400722794159857838650852114432;
    let (u) = pow(-2, 3);
    assert (u) = -8;
    let (v) = pow(-25, 31);
    assert (v) = -21684043449710088680149056017398834228515625;

    let (a) = pow_manual_implementation(2, 3);
    assert a = 8;
    let (b) = pow_manual_implementation(10, 6);
    assert b = 1000000;
    let (c) = pow_manual_implementation(152, 25);
    assert c = 3516330588649452857943715400722794159857838650852114432;
    let (d) = pow_manual_implementation(-2, 3);
    assert (d) = -8;
    let (e) = pow_manual_implementation(-25, 31);
    assert (e) = -21684043449710088680149056017398834228515625;

    return ();
}
