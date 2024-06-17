// Code taken from https://github.com/NethermindEth/research-basic-Cairo-operations-big-integers/blob/main/lib/uint384.cairo
from starkware.cairo.common.bitwise import bitwise_and, bitwise_or, bitwise_xor
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import assert_in_range, assert_le, assert_nn_le, assert_not_zero
from starkware.cairo.common.math import unsigned_div_rem as frem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.uint256 import Uint256, uint256_add, word_reverse_endian
from starkware.cairo.common.pow import pow
from starkware.cairo.common.registers import get_ap, get_fp_and_pc

// This library is adapted from Cairo's common library Uint256 and it follows it as closely as possible.
// The library implements basic operations between 384-bit integers.
// Most operations use unsigned integers. Only a few operations are implemented for signed integers

// Represents an integer in the range [0, 2^384).
struct Uint384 {
    // The low 128 bits of the value.
    d0: felt,
    // The middle 128 bits of the value.
    d1: felt,
    // The # 128 bits of the value.
    d2: felt,
}

struct Uint384_expand {
    B0: felt,
    b01: felt,
    b12: felt,
    b23: felt,
    b34: felt,
    b45: felt,
    b5: felt,
}

const SHIFT = 2 ** 128;
const ALL_ONES = 2 ** 128 - 1;
const HALF_SHIFT = 2 ** 64;

namespace u384 {
    // Verifies that the given integer is valid.
    func check{range_check_ptr}(a: Uint384) {
        [range_check_ptr] = a.d0;
        [range_check_ptr + 1] = a.d1;
        [range_check_ptr + 2] = a.d2;
        let range_check_ptr = range_check_ptr + 3;
        return ();
    }

    // Adds two integers. Returns the result as a 384-bit integer and the (1-bit) carry.
    func add{range_check_ptr}(a: Uint384, b: Uint384) -> (res: Uint384, carry: felt) {
        alloc_locals;
        local res: Uint384;
        local carry_d0: felt;
        local carry_d1: felt;
        local carry_d2: felt;
        %{
            sum_d0 = ids.a.d0 + ids.b.d0
            ids.carry_d0 = 1 if sum_d0 >= ids.SHIFT else 0
            sum_d1 = ids.a.d1 + ids.b.d1 + ids.carry_d0
            ids.carry_d1 = 1 if sum_d1 >= ids.SHIFT else 0
            sum_d2 = ids.a.d2 + ids.b.d2 + ids.carry_d1
            ids.carry_d2 = 1 if sum_d2 >= ids.SHIFT else 0
        %}

        // Either 0 or 1
        assert carry_d0 * carry_d0 = carry_d0;
        assert carry_d1 * carry_d1 = carry_d1;
        assert carry_d2 * carry_d2 = carry_d2;

        assert res.d0 = a.d0 + b.d0 - carry_d0 * SHIFT;
        assert res.d1 = a.d1 + b.d1 + carry_d0 - carry_d1 * SHIFT;
        assert res.d2 = a.d2 + b.d2 + carry_d1 - carry_d2 * SHIFT;

        check(res);

        return (res, carry_d2);
    }

    // Return true if both integers are equal.
    func eq(a: Uint384, b: Uint384) -> (res: felt) {
        if (a.d2 != b.d2) {
            return (0,);
        }
        if (a.d1 != b.d1) {
            return (0,);
        }
        if (a.d0 != b.d0) {
            return (0,);
        }
        return (1,);
    }

    // Subtracts two integers. Returns the result as a 384-bit integer.
    func sub{range_check_ptr}(a: Uint384, b: Uint384) -> (res: Uint384) {
        let (b_neg) = neg(b);
        let (res, _) = add(a, b_neg);
        return (res,);
    }

    // Returns the bitwise NOT of an integer.
    func not(a: Uint384) -> (res: Uint384) {
        return (Uint384(d0=ALL_ONES - a.d0, d1=ALL_ONES - a.d1, d2=ALL_ONES - a.d2),);
    }

    // Returns the negation of an integer.
    // Note that the negation of -2**383 is -2**383.
    func neg{range_check_ptr}(a: Uint384) -> (res: Uint384) {
        let (not_num) = not(a);
        let (res, _) = add(not_num, Uint384(d0=1, d1=0, d2=0));
        return (res,);
    }

    // Returns 1 if the signed integer is nonnegative.
    @known_ap_change
    func signed_nn{range_check_ptr}(a: Uint384) -> (res: felt) {
        %{ memory[ap] = 1 if 0 <= (ids.a.d2 % PRIME) < 2 ** 127 else 0 %}
        jmp non_negative if [ap] != 0, ap++;

        assert [range_check_ptr] = a.d2 - 2 ** 127;
        let range_check_ptr = range_check_ptr + 1;
        return (res=0);

        non_negative:
        assert [range_check_ptr] = a.d2 + 2 ** 127;
        let range_check_ptr = range_check_ptr + 1;
        return (res=1);
    }

    // Adds two integers. Returns the result as a 384-bit integer and the (1-bit) carry.
    // Doesn't verify that the result is a proper Uint384, that's now the responsibility of the calling function
    func _add_no_uint384_check{range_check_ptr}(a: Uint384, b: Uint384) -> (
        res: Uint384, carry: felt
    ) {
        alloc_locals;
        local res: Uint384;
        local carry_d0: felt;
        local carry_d1: felt;
        local carry_d2: felt;
        %{
            sum_d0 = ids.a.d0 + ids.b.d0
            ids.carry_d0 = 1 if sum_d0 >= ids.SHIFT else 0
            sum_d1 = ids.a.d1 + ids.b.d1 + ids.carry_d0
            ids.carry_d1 = 1 if sum_d1 >= ids.SHIFT else 0
            sum_d2 = ids.a.d2 + ids.b.d2 + ids.carry_d1
            ids.carry_d2 = 1 if sum_d2 >= ids.SHIFT else 0
        %}

        // Either 0 or 1
        assert carry_d0 * carry_d0 = carry_d0;
        assert carry_d1 * carry_d1 = carry_d1;
        assert carry_d2 * carry_d2 = carry_d2;

        assert res.d0 = a.d0 + b.d0 - carry_d0 * SHIFT;
        assert res.d1 = a.d1 + b.d1 + carry_d0 - carry_d1 * SHIFT;
        assert res.d2 = a.d2 + b.d2 + carry_d1 - carry_d2 * SHIFT;

        return (res, carry_d2);
    }

    // Splits a field element in the range [0, 2^192) to its low 64-bit and high 128-bit parts.
    func split_64{range_check_ptr}(a: felt) -> (low: felt, high: felt) {
        alloc_locals;
        local low: felt;
        local high: felt;

        %{
            ids.low = ids.a & ((1<<64) - 1)
            ids.high = ids.a >> 64
        %}
        assert a = low + high * HALF_SHIFT;
        assert [range_check_ptr + 0] = low;
        assert [range_check_ptr + 1] = HALF_SHIFT - 1 - low;
        assert [range_check_ptr + 2] = high;
        let range_check_ptr = range_check_ptr + 3;
        return (low, high);
    }

    // Splits a field element in the range [0, 2^224) to its low 128-bit and high 96-bit parts.
    func split_128{range_check_ptr}(a: felt) -> (low: felt, high: felt) {
        alloc_locals;
        const UPPER_BOUND = 2 ** 224;
        const HIGH_BOUND = UPPER_BOUND / SHIFT;
        local low: felt;
        local high: felt;

        %{
            ids.low = ids.a & ((1<<128) - 1)
            ids.high = ids.a >> 128
        %}
        assert a = low + high * SHIFT;
        assert [range_check_ptr + 0] = high;
        assert [range_check_ptr + 1] = HIGH_BOUND - 1 - high;
        assert [range_check_ptr + 2] = low;
        let range_check_ptr = range_check_ptr + 3;
        return (low, high);
    }

    // Multiplies two integers. Returns the result as two 384-bit integers: the result has 2*384 bits,
    // the returned integers represent the lower 384-bits and the higher 384-bits, respectively.
    func mul{range_check_ptr}(a: Uint384, b: Uint384) -> (low: Uint384, high: Uint384) {
        let (a0, a1) = split_64(a.d0);
        let (a2, a3) = split_64(a.d1);
        let (a4, a5) = split_64(a.d2);
        let (b0, b1) = split_64(b.d0);
        let (b2, b3) = split_64(b.d1);
        let (b4, b5) = split_64(b.d2);

        let (res0, carry) = split_64(a0 * b0);
        let (res1, carry) = split_64(a1 * b0 + a0 * b1 + carry);
        let (res2, carry) = split_64(a2 * b0 + a1 * b1 + a0 * b2 + carry);
        let (res3, carry) = split_64(a3 * b0 + a2 * b1 + a1 * b2 + a0 * b3 + carry);
        let (res4, carry) = split_64(a4 * b0 + a3 * b1 + a2 * b2 + a1 * b3 + a0 * b4 + carry);
        let (res5, carry) = split_64(
            a5 * b0 + a4 * b1 + a3 * b2 + a2 * b3 + a1 * b4 + a0 * b5 + carry
        );
        let (res6, carry) = split_64(a5 * b1 + a4 * b2 + a3 * b3 + a2 * b4 + a1 * b5 + carry);
        let (res7, carry) = split_64(a5 * b2 + a4 * b3 + a3 * b4 + a2 * b5 + carry);
        let (res8, carry) = split_64(a5 * b3 + a4 * b4 + a3 * b5 + carry);
        let (res9, carry) = split_64(a5 * b4 + a4 * b5 + carry);
        let (res10, carry) = split_64(a5 * b5 + carry);

        return (
            low=Uint384(
                d0=res0 + HALF_SHIFT * res1,
                d1=res2 + HALF_SHIFT * res3,
                d2=res4 + HALF_SHIFT * res5,
            ),
            high=Uint384(
                d0=res6 + HALF_SHIFT * res7,
                d1=res8 + HALF_SHIFT * res9,
                d2=res10 + HALF_SHIFT * carry,
            ),
        );
    }
    func mul_expanded{range_check_ptr}(a: Uint384, b: Uint384_expand) -> (
        low: Uint384, high: Uint384
    ) {
        let (a0, a1) = split_64(a.d0);
        let (a2, a3) = split_64(a.d1);
        let (a4, a5) = split_64(a.d2);

        let (res0, carry) = split_128(a1 * b.B0 + a0 * b.b01);
        let (res2, carry) = split_128(a3 * b.B0 + a2 * b.b01 + a1 * b.b12 + a0 * b.b23 + carry);
        let (res4, carry) = split_128(
            a5 * b.B0 + a4 * b.b01 + a3 * b.b12 + a2 * b.b23 + a1 * b.b34 + a0 * b.b45 + carry
        );
        let (res6, carry) = split_128(
            a5 * b.b12 + a4 * b.b23 + a3 * b.b34 + a2 * b.b45 + a1 * b.b5 + carry
        );
        let (res8, carry) = split_128(a5 * b.b34 + a4 * b.b45 + a3 * b.b5 + carry);
        // let (res10, carry) = split_64(a5 * b.b5 + carry)

        return (
            low=Uint384(d0=res0, d1=res2, d2=res4),
            high=Uint384(d0=res6, d1=res8, d2=a5 * b.b5 + carry),
        );
    }

    func mul_d{range_check_ptr}(a: Uint384, b: Uint384) -> (low: Uint384, high: Uint384) {
        alloc_locals;
        let (a0, a1) = split_64(a.d0);
        let (a2, a3) = split_64(a.d1);
        let (a4, a5) = split_64(a.d2);
        let (b0, b1) = split_64(b.d0);
        let (b2, b3) = split_64(b.d1);
        let (b4, b5) = split_64(b.d2);

        local B0 = b0 * HALF_SHIFT;
        local b12 = b1 + b2 * HALF_SHIFT;
        local b34 = b3 + b4 * HALF_SHIFT;

        let (res0, carry) = split_128(a1 * B0 + a0 * b.d0);
        let (res2, carry) = split_128(a3 * B0 + a2 * b.d0 + a1 * b12 + a0 * b.d1 + carry);
        let (res4, carry) = split_128(
            a5 * B0 + a4 * b.d0 + a3 * b12 + a2 * b.d1 + a1 * b34 + a0 * b.d2 + carry
        );
        let (res6, carry) = split_128(
            a5 * b12 + a4 * b.d1 + a3 * b34 + a2 * b.d2 + a1 * b5 + carry
        );
        let (res8, carry) = split_128(a5 * b34 + a4 * b.d2 + a3 * b5 + carry);
        // let (res10, carry) = split_64(a5 * b5 + carry)

        return (
            low=Uint384(d0=res0, d1=res2, d2=res4),
            high=Uint384(d0=res6, d1=res8, d2=a5 * b5 + carry),
        );
    }

    func lt{range_check_ptr}(a: Uint384, b: Uint384) -> (res: felt) {
        if (a.d2 == b.d2) {
            if (a.d1 == b.d1) {
                return (is_le(a.d0 + 1, b.d0),);
            }
            return (is_le(a.d1 + 1, b.d1),);
        }
        return (is_le(a.d2 + 1, b.d2),);
    }

    // Returns 1 if the first unsigned integer is less than or equal to the second unsigned integer.
    func le{range_check_ptr}(a: Uint384, b: Uint384) -> (res: felt) {
        let (not_le) = lt(a=b, b=a);
        return (1 - not_le,);
    }

    // Unsigned integer division between two integers. Returns the quotient and the remainder.
    // Conforms to EVM specifications: division by 0 yields 0.
    func unsigned_div_rem{range_check_ptr}(a: Uint384, div: Uint384) -> (
        quotient: Uint384, remainder: Uint384
    ) {
        alloc_locals;
        local quotient: Uint384;
        local remainder: Uint384;

        // If div == 0, return (0, 0, 0).
        if (div.d0 + div.d1 + div.d2 == 0) {
            return (quotient=Uint384(0, 0, 0), remainder=Uint384(0, 0, 0));
        }

        %{
            def split(num: int, num_bits_shift: int, length: int):
                a = []
                for _ in range(length):
                    a.append( num & ((1 << num_bits_shift) - 1) )
                    num = num >> num_bits_shift
                return tuple(a)

            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.d0, z.d1, z.d2)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            a = pack(ids.a, num_bits_shift = 128)
            div = pack(ids.div, num_bits_shift = 128)
            quotient, remainder = divmod(a, div)

            quotient_split = split(quotient, num_bits_shift=128, length=3)
            assert len(quotient_split) == 3

            ids.quotient.d0 = quotient_split[0]
            ids.quotient.d1 = quotient_split[1]
            ids.quotient.d2 = quotient_split[2]

            remainder_split = split(remainder, num_bits_shift=128, length=3)
            ids.remainder.d0 = remainder_split[0]
            ids.remainder.d1 = remainder_split[1]
            ids.remainder.d2 = remainder_split[2]
        %}
        check(quotient);
        check(remainder);
        let (res_mul: Uint384, carry: Uint384) = mul_d(quotient, div);
        assert carry = Uint384(0, 0, 0);

        let (check_val: Uint384, add_carry: felt) = _add_no_uint384_check(res_mul, remainder);
        assert check_val = a;
        assert add_carry = 0;

        let (is_valid) = lt(remainder, div);
        assert is_valid = 1;
        return (quotient=quotient, remainder=remainder);
    }

    func square_e{range_check_ptr}(a: Uint384) -> (low: Uint384, high: Uint384) {
        alloc_locals;
        let (a0, a1) = split_64(a.d0);
        let (a2, a3) = split_64(a.d1);
        let (a4, a5) = split_64(a.d2);

        const HALF_SHIFT2 = 2 * HALF_SHIFT;
        local a0_2 = a0 * 2;
        local a34 = a3 + a4 * HALF_SHIFT2;

        let (res0, carry) = split_128(a0 * (a0 + a1 * HALF_SHIFT2));
        let (res2, carry) = split_128(a.d1 * a0_2 + a1 * (a1 + a2 * HALF_SHIFT2) + carry);
        let (res4, carry) = split_128(
            a.d2 * a0_2 + (a3 + a34) * a1 + a2 * (a2 + a3 * HALF_SHIFT2) + carry
        );
        let (res6, carry) = split_128((a5 * a1 + a.d2 * a2) * 2 + a3 * a34 + carry);
        let (res8, carry) = split_128(a5 * (a3 + a34) + a4 * a4 + carry);
        // let (res10, carry) = split_64(a5*a5 + carry)

        return (
            low=Uint384(d0=res0, d1=res2, d2=res4),
            high=Uint384(d0=res6, d1=res8, d2=a5 * a5 + carry),
        );
    }

    // Returns the floor value of the square root of a Uint384 integer.
    func sqrt{range_check_ptr}(a: Uint384) -> (res: Uint384) {
        alloc_locals;
        let (__fp__, _) = get_fp_and_pc();
        local root: Uint384;

        %{
            from starkware.python.math_utils import isqrt

            def split(num: int, num_bits_shift: int, length: int):
                a = []
                for _ in range(length):
                    a.append( num & ((1 << num_bits_shift) - 1) )
                    num = num >> num_bits_shift
                return tuple(a)

            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.d0, z.d1, z.d2)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            a = pack(ids.a, num_bits_shift=128)
            root = isqrt(a)
            assert 0 <= root < 2 ** 192
            root_split = split(root, num_bits_shift=128, length=3)
            ids.root.d0 = root_split[0]
            ids.root.d1 = root_split[1]
            ids.root.d2 = root_split[2]
        %}

        // Verify that 0 <= root < 2**192.
        assert root.d2 = 0;
        [range_check_ptr] = root.d0;

        // We don't need to check that 0 <= d1 < 2**64, since this gets checked
        // when we check that carry==0 later
        assert [range_check_ptr + 1] = root.d1;
        let range_check_ptr = range_check_ptr + 2;

        // Verify that n >= root**2.
        let (root_squared, carry) = square_e(root);
        assert carry = Uint384(0, 0, 0);
        let (check_lower_bound) = le(root_squared, a);
        assert check_lower_bound = 1;

        // Verify that n <= (root+1)**2 - 1.
        // In the case where root = 2**192 - 1, we will have next_root_squared=0, since
        // (root+1)**2 = 2**384. Therefore next_root_squared - 1 = 2**384 - 1, as desired.
        let (next_root, add_carry) = add(root, Uint384(1, 0, 0));
        assert add_carry = 0;
        let (next_root_squared, _) = square_e(next_root);
        let (next_root_squared_minus_one) = sub(next_root_squared, Uint384(1, 0, 0));
        let (check_upper_bound) = le(a, next_root_squared_minus_one);
        assert check_upper_bound = 1;

        return (res=root);
    }
}

func main() {
    return ();
}
