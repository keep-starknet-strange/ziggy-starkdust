%builtins range_check bitwise

from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_blake2s.blake2s import blake2s_felts
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;
    let inputs: felt* = alloc();
    assert inputs[0] = 3456722;
    assert inputs[1] = 435425528;
    assert inputs[2] = 3232553;
    assert inputs[3] = 2576195;
    assert inputs[4] = 73471943;
    assert inputs[5] = 17549868;
    assert inputs[6] = 87158958;
    assert inputs[7] = 6353668;
    assert inputs[8] = 343656565;
    assert inputs[9] = 1255962;
    assert inputs[10] = 25439785;
    assert inputs[11] = 1154578;
    assert inputs[12] = 585849303;
    assert inputs[13] = 763502;
    assert inputs[14] = 43753647;
    assert inputs[15] = 74256930;
    let (local blake2s_ptr_start) = alloc();
    let blake2s_ptr = blake2s_ptr_start;
    // Big endian
    let (result) = blake2s_felts{range_check_ptr=range_check_ptr, blake2s_ptr=blake2s_ptr}(
        16, inputs, TRUE
    );
    assert result.low = 23022179997536219430502258022509199703;
    assert result.high = 136831746058902715979837770794974289597;

    // Little endian
    let (result) = blake2s_felts{range_check_ptr=range_check_ptr, blake2s_ptr=blake2s_ptr}(
        16, inputs, FALSE
    );
    assert result.low = 315510691254085211243916597439546947220;
    assert result.high = 42237338665522721102428636006748876126;

    return ();
}
