from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.bool import TRUE
from cairo_programs.uint384 import u384, Uint384
from cairo_programs.uint384_extension import u384_ext
from cairo_programs.field_arithmetic import field_arithmetic

func run_get_square{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    prime: Uint384, generator: Uint384, num: Uint384, iterations: felt
) {
    alloc_locals;
    if (iterations == 0) {
        return ();
    }

    let (square) = field_arithmetic.mul(num, num, prime);

    let (success, root_1) = field_arithmetic.get_square_root(square, prime, generator);
    assert success = 1;

    // We calculate this before in order to prevent revoked range_check_ptr reference due to branching
    let (root_2) = u384.sub(prime, root_1);
    let (is_first_root) = u384.eq(root_1, num);

    if (is_first_root != TRUE) {
        assert root_2 = num;
    }

    return run_get_square(prime, generator, square, iterations - 1);
}

func main{range_check_ptr: felt, bitwise_ptr: BitwiseBuiltin*}() {
    let p = Uint384(18446744069414584321, 0, 0);  // Goldilocks Prime
    let x = Uint384(5, 0, 0);
    let g = Uint384(7, 0, 0);
    run_get_square(p, g, x, 1000);
    return ();
}
