%builtins output bitwise
from starkware.cairo.common.bitwise import bitwise_and
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.serialize import serialize_word

func main{output_ptr: felt*, bitwise_ptr: BitwiseBuiltin*}() {
    let (result) = bitwise_and(1, 2);
    serialize_word(result);
    return ();
}
