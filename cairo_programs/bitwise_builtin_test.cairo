%builtins bitwise
from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor, bitwise_or, bitwise_operations
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

func main{bitwise_ptr: BitwiseBuiltin*}() {
    let (and_a) = bitwise_and(12, 10);  // Binary (1100, 1010).
    assert and_a = 8;  // Binary 1000.
    let (xor_a) = bitwise_xor(12, 10);
    assert xor_a = 6;
    let (or_a) = bitwise_or(12, 10);
    assert or_a = 14;

    let (and_b, xor_b, or_b) = bitwise_operations(9, 3);
    assert and_b = 1;
    assert xor_b = 10;
    assert or_b = 11;
    return ();
}
