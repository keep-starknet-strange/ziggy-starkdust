%builtins range_check

from starkware.cairo.common.cairo_secp.signature import div_mod_n, get_point_from_x
from starkware.cairo.common.cairo_secp.bigint import BigInt3

func main{range_check_ptr: felt}() {
    let a: BigInt3 = BigInt3(100, 99, 98);
    let b: BigInt3 = BigInt3(10, 9, 8);
    let (res) = div_mod_n(a, b);
    assert res.d0 = 3413472211745629263979533;
    assert res.d1 = 17305268010345238170172332;
    assert res.d2 = 11991751872105858217578135;

    let x: BigInt3 = BigInt3(100, 99, 98);
    let v: felt = 10;
    let (point) = get_point_from_x(x, v);
    assert point.x.d0 = 100;
    assert point.x.d1 = 99;
    assert point.x.d2 = 98;
    assert point.y.d0 = 50471654703173585387369794;
    assert point.y.d1 = 68898944762041070370364387;
    assert point.y.d2 = 16932612780945290933872774;
    return ();
}
