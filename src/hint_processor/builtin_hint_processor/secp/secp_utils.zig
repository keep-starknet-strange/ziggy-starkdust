const std = @import("std");
const BigInt = std.math.big.int.Managed;
const BASE = @import("../../../math/fields/constants.zig").BASE;
const MathError = @import("../../../vm/error.zig").MathError;

/// Takes a 256-bit integer and returns its canonical representation as:
/// d0 + BASE * d1 + BASE**2 * d2,
/// where BASE = 2**86.
pub fn bigInt3Split(integer: BigInt) !std.ArrayList(BigInt) {
    var canonical_repr = std.ArrayList(BigInt).init(std.heap.page_allocator);
    defer canonical_repr.deinit();

    var num = integer;
    const base_minus_one = BASE - 1;
    while (num.bitCountAbs() > 0) {
        const item = num & base_minus_one;
        try canonical_repr.append(item);
        num >>= 86;
    }

    if (num != 0) {
        return MathError.SecpSplitOutOfRange;
    }
    return canonical_repr.toOwnedSlice();
}
