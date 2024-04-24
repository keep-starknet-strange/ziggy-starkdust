const std = @import("std");

pub const BASE = @import("../../../math/fields/constants.zig").BASE;
const Int = std.math.big.int.Managed;

pub const SECP_P =
    115792089237316195423570985008687907853269984665640564039457584007908834671663;

pub const SECP_P_V2 = 57896044618658097711785492504343953926634992332820282019728792003956564819949;
pub const ALPHA = 0;
pub const ALPHA_V2 = 42204101795669822316448953119945047945709099015225996174933988943478124189485;
pub const BASE_MINUS_ONE = 77371252455336267181195263;
pub const N = 115792089237316195423570985008687907852837564279074904382605163141518161494337;

pub const SECP256R1_ALPHA = 115792089210356248762697446949407573530086143415290314195533631308867097853948;
pub const SECP256R1_N = 115792089210356248762697446949407573529996955224135760342422259061068512044369;
pub const SECP256R1_P = 115792089210356248762697446949407573530086143415290314195533631308867097853951;

// Constants in package "starkware.cairo.common.cairo_secp.constants".
pub const BASE_86 = "starkware.cairo.common.cairo_secp.constants.BASE";
pub const BETA = "starkware.cairo.common.cairo_secp.constants.BETA";
pub const N0 = "starkware.cairo.common.cairo_secp.constants.N0";
pub const N1 = "starkware.cairo.common.cairo_secp.constants.N1";
pub const N2 = "starkware.cairo.common.cairo_secp.constants.N2";
pub const P0 = "starkware.cairo.common.cairo_secp.constants.P0";
pub const P1 = "starkware.cairo.common.cairo_secp.constants.P1";
pub const P2 = "starkware.cairo.common.cairo_secp.constants.P2";
pub const SECP_REM = "starkware.cairo.common.cairo_secp.constants.SECP_REM";

const MathError = @import("../../../vm/error.zig").MathError;

/// Takes a 256-bit integer and returns its canonical representation as:
/// d0 + BASE * d1 + BASE**2 * d2,
/// where BASE = 2**86.
pub fn bigInt3Split(allocator: std.mem.Allocator, integer: *const Int) ![3]Int {
    var canonical_repr: [3]Int = undefined;

    // init all data
    inline for (0..3) |i| {
        canonical_repr[i] = try Int.init(allocator);
        errdefer inline for (0..i) |x| canonical_repr[x].deinit();
    }

    errdefer inline for (0..3) |x| canonical_repr[x].deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var num = try integer.cloneWithDifferentAllocator(allocator);
    defer num.deinit();

    var base_minus_one = try Int.initSet(allocator, BASE - 1);
    defer base_minus_one.deinit();

    inline for (&canonical_repr) |*item| {
        try item.*.bitAnd(&num, &base_minus_one);
        //  shift right got a bug, shift size more than 64 glitching, so we need just make n shifts less than 64
        try num.shiftRight(&num, 43);
        try num.shiftRight(&num, 43);
    }

    if (!num.eqlZero()) {
        return MathError.SecpSplitOutOfRange;
    }

    return canonical_repr;
}
