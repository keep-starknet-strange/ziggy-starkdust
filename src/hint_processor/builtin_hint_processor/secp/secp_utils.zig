const std = @import("std");
const BASE = @import("../../../math/fields/constants.zig").BASE;
const Int = std.math.big.int.Managed;

pub const BASE_86 = "starkware.cairo.common.cairo_secp.constants.BASE";

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
