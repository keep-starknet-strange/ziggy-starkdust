%builtins range_check bitwise keccak
from starkware.cairo.common.cairo_builtins import KeccakBuiltin, BitwiseBuiltin
from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}() {
    let elements: Uint256* = alloc();
    assert elements[0] = Uint256(713458135386519, 18359173571);
    assert elements[1] = Uint256(1536741637546373185, 84357893467438914);
    assert elements[2] = Uint256(2842949328439284983294, 39248298942938492384);
    assert elements[3] = Uint256(27518568234293478923754395731931, 981587843715983274);
    assert elements[4] = Uint256(326848123647324823482, 93453458349589345);
    let (res) = keccak_uint256s(5, elements);
    assert res.high = 23012215180764429403047187376747988760;
    assert res.low = 13431206634823648732212765105043225161;

    return ();
}
