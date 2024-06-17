// Core imports.
const std = @import("std");
// Local imports.
const fields = @import("fields.zig");
pub const STARKNET_PRIME = 0x800000000000011000000000000000000000000000000000000000000000001;
pub const FELT_BYTE_SIZE = 32;
pub const PRIME_STR = "0x800000000000011000000000000000000000000000000000000000000000001";

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const starknet = @import("starknet");
pub const Felt252 = starknet.fields.Felt252;

// TODO: desc
pub fn bigIntToBytesLe(allocator: std.mem.Allocator, bigint: std.math.big.int.Managed) ![]u8 {
    var buf = try allocator.alloc(u8, @sizeOf(usize) * bigint.len());
    errdefer allocator.free(buf);

    for (0..bigint.len()) |i|
        @memcpy(buf[i * @sizeOf(usize) .. (i + 1) * @sizeOf(usize)], @as([@sizeOf(usize)]u8, @bitCast(bigint.limbs[i]))[0..]);

    return buf;
}

pub fn fromBigInt(allocator: std.mem.Allocator, bigint: std.math.big.int.Managed) !Felt252 {
    var tmp = try std.math.big.int.Managed.init(allocator);
    defer tmp.deinit();

    var tmp2 = try std.math.big.int.Managed.initSet(allocator, STARKNET_PRIME);
    defer tmp2.deinit();

    try tmp.divFloor(&tmp2, &bigint, &tmp2);

    if (!tmp2.isPositive()) tmp2.negate();

    const bytes =
        try bigIntToBytesLe(allocator, tmp2);

    defer allocator.free(bytes);

    return fromBytesLeSlice(bytes);
}

/// Creates a new [Felt] from its little-endian representation in a [u8] slice.
/// This is as performant as [from_bytes_be](Felt::from_bytes_be_slice).
/// All bytes in the slice are consumed, as if first creating a big integer
/// from them, but the conversion is performed in constant space on the stack.
pub fn fromBytesLeSlice(bytes: []const u8) Felt252 {
    // NB: lambdaworks ignores the remaining bytes when len > 32, so we loop
    // multiplying by BASE, effectively decomposing in base 2^256 to build
    // digits with a length of 32 bytes. This is analogous to splitting the
    // number `xyz` as `x * 10^2 + y * 10^1 + z * 10^0`.
    const BASE: Felt252 = .{ .fe = .{ .limbs = .{
        18446741271209837569,
        5151653887,
        18446744073700081664,
        576413109808302096,
    } } };

    // Sanity check; gets removed in release builds.
    comptime {
        std.debug.assert(BASE.eql(Felt252.two().powToInt(256)));
    }

    var factor = Felt252.one();
    var res = Felt252.zero();

    const chunks = bytes.len / 32;
    const remainder = bytes.len % 32;

    for (0..chunks) |i| {
        const digit = Felt252.fromBytesLe(bytes[i * 32 .. (i + 1) * 32][0..32].*);

        res = res.add(&digit.mul(&factor));
        factor = factor.mul(&BASE);
    }

    if (remainder == 0) return res;

    var buf = [_]u8{0} ** 32;

    std.mem.copyForwards(u8, buf[0..], bytes[chunks * 32 ..]);

    const digit = Felt252.fromBytesLe(buf);
    return res.add(&digit.mul(&factor));
}
