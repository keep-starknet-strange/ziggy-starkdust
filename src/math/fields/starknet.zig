// Core imports.
const std = @import("std");
// Local imports.
const fields = @import("fields.zig");

// Base field for the Stark curve.
// The prime is 0x800000000000011000000000000000000000000000000000000000000000001.
pub const Felt252 = fields.Field(
    @import("stark_felt_252_gen_fp.zig"),
    0x800000000000011000000000000000000000000000000000000000000000001,
);

test "Felt252 fromInteger" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10),
        Felt252{ .fe = .{
            0xfffffffffffffec1,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0x7ffffffffffead0,
        } },
    );

    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)),
        Felt252{ .fe = .{
            0xfffffd737e000421,
            0x1330fffff,
            0xffffffffff6f8000,
            0x7ffd4ab5e008a30,
        } },
    );
}

test "Felt252 toInteger" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).toInteger(),
        10,
    );

    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).toInteger(),
        0x7fffffffffffdf0ffffffffffffffffffffffffffffffffffffffffffffffe0,
    );
}

test "Felt252 one" {
    try std.testing.expectEqual(
        Felt252.one(),
        Felt252{ .fe = .{
            0xffffffffffffffe1,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0x7fffffffffffdf0,
        } },
    );
}

test "Felt252 zero" {
    try std.testing.expectEqual(
        Felt252.zero(),
        Felt252{ .fe = .{
            0,
            0,
            0,
            0,
        } },
    );
}

test "Felt252 equal" {
    try std.testing.expect(Felt252.zero().equal(Felt252.zero()));
    try std.testing.expect(Felt252.fromInteger(10).equal(Felt252.fromInteger(10)));
    try std.testing.expect(!Felt252.fromInteger(10).equal(Felt252.fromInteger(100)));
}

test "Felt252 isZero" {
    try std.testing.expect(Felt252.zero().isZero());
    try std.testing.expect(!Felt252.one().isZero());
    try std.testing.expect(!Felt252.fromInteger(10).isZero());
}

test "Felt252 isOne" {
    try std.testing.expect(Felt252.one().isOne());
    try std.testing.expect(!Felt252.zero().isOne());
    try std.testing.expect(!Felt252.fromInteger(10).isOne());
}

test "Felt252 fromBytes" {
    const a: [32]u8 = .{
        0x4E,
        0x5F,
        0x5F,
        0x5F,
        0x5F,
        0x5F,
        0x5F,
        0x5F,
        0x5F,
        0x19,
        0x67,
        0x2F,
        0xDF,
        0x76,
        0xCE,
        0x51,
        0xBA,
        0x69,
        0xC6,
        0x07,
        0x6A,
        0x0F,
        0x77,
        0xEA,
        0xBC,
        0xB2,
        0xA9,
        0x3B,
        0xE6,
        0xF8,
        0x96,
        0x00,
    };

    try std.testing.expectEqual(
        Felt252.fromBytes(a).toInteger(),
        0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e,
    );

    try std.testing.expectEqual(
        Felt252.fromBytes(a),
        Felt252.fromInteger(0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e),
    );
}

test "Felt252 toBytes" {
    try std.testing.expectEqual(
        Felt252.fromInteger(0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e).toBytes(),
        .{
            0x4E,
            0x5F,
            0x5F,
            0x5F,
            0x5F,
            0x5F,
            0x5F,
            0x5F,
            0x5F,
            0x19,
            0x67,
            0x2F,
            0xDF,
            0x76,
            0xCE,
            0x51,
            0xBA,
            0x69,
            0xC6,
            0x07,
            0x6A,
            0x0F,
            0x77,
            0xEA,
            0xBC,
            0xB2,
            0xA9,
            0x3B,
            0xE6,
            0xF8,
            0x96,
            0x00,
        },
    );
}

test "Felt252 tryIntoU64" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).tryIntoU64(),
        10,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u64)).tryIntoU64(),
        std.math.maxInt(u64),
    );
    try std.testing.expectError(
        error.ValueTooLarge,
        Felt252.fromInteger(std.math.maxInt(u64) + 1).tryIntoU64(),
    );
}

test "Felt252 arithmetic operations" {
    const a = Felt252.one();
    const b = Felt252.fromInteger(2);
    const c = a.add(b);
    try std.testing.expect(c.equal(Felt252.fromInteger(3)));
}

test "Felt252 add" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).add(Felt252.fromInteger(5)).toInteger(),
        0xf,
    );
    try std.testing.expect(Felt252.fromInteger(1).add(Felt252.zero()).isOne());
    try std.testing.expect(Felt252.zero().add(Felt252.zero()).isZero());
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).add(Felt252.fromInteger(std.math.maxInt(u256))).toInteger(),
        0x7fffffffffffbd0ffffffffffffffffffffffffffffffffffffffffffffffbf,
    );
}

test "Felt252 sub" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).sub(Felt252.fromInteger(5)).toInteger(),
        0x5,
    );
    try std.testing.expect(Felt252.fromInteger(std.math.maxInt(u256)).sub(Felt252.fromInteger(std.math.maxInt(u256))).isZero());
    try std.testing.expect(Felt252.zero().sub(Felt252.zero()).isZero());
}

test "Felt252 mul" {
    try std.testing.expect(Felt252.zero().mul(Felt252.zero()).isZero());
    try std.testing.expect(Felt252.one().mul(Felt252.one()).isOne());
    try std.testing.expectEqual(
        Felt252.fromInteger(10).mul(Felt252.fromInteger(5)).toInteger(),
        0x32,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).mul(Felt252.fromInteger(2)).toInteger(),
        0x7fffffffffffbd0ffffffffffffffffffffffffffffffffffffffffffffffbf,
    );
}

test "Felt252 mulBy5" {
    try std.testing.expect(Felt252.zero().mulBy5().isZero());
    try std.testing.expectEqual(
        Felt252.one().mulBy5().toInteger(),
        5,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).mulBy5().toInteger(),
        0x7fffffffffff570ffffffffffffffffffffffffffffffffffffffffffffff5c,
    );
}

test "Felt252 neg" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).neg().toInteger(),
        0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffff7,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).neg().toInteger(),
        0x220000000000000000000000000000000000000000000000021,
    );
}

test "Felt252 square" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).square().toInteger(),
        0x64,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).square().toInteger(),
        0x7ffd4ab5e008c50ffffffffff6f800000000001330ffffffffffd737e000442,
    );
}

test "Felt252 pow2" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).pow2(10).toInteger(),
        0x4cdffe7c7b3f76a6ce28dde767fa09b60e963927bbd16d8b0d3a0fc13c6fa0,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).pow2(3).toInteger(),
        0x25f7dc4108a227e91fb20740a4866274f449e9d427775a58bb7cb4eaff1e653,
    );
}

test "Felt252 pow" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).pow(10).toInteger(),
        0x2540be400,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u64)).pow(5).toInteger(),
        0x48ea9fffffffffffffff5ffffffffffffffe5000000000000449f,
    );
}

test "Felt252 inv" {
    try std.testing.expectEqual(
        Felt252.fromInteger(10).inv().?.toInteger(),
        0x733333333333342800000000000000000000000000000000000000000000001,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(std.math.maxInt(u256)).inv().?.toInteger(),
        0x538bf4edb6bf78474ef0f1979a0db0bdd364ce7aeda9f3c6c04bea822682ba,
    );
    try std.testing.expectEqual(
        Felt252.zero().inv(),
        null,
    );
}

test "Felt252 batchInv" {
    var out: [2]Felt252 = undefined;
    const in: [2]Felt252 = .{ Felt252.fromInteger(10), Felt252.fromInteger(5) };
    try Felt252.batchInv(&out, &in);
    try std.testing.expectEqual(
        out[0].toInteger(),
        0x733333333333342800000000000000000000000000000000000000000000001,
    );
    try std.testing.expectEqual(
        out[1].toInteger(),
        0x666666666666674000000000000000000000000000000000000000000000001,
    );
}

test "Felt252 batchInv with zero" {
    var out: [3]Felt252 = undefined;
    const in: [3]Felt252 = .{ Felt252.fromInteger(10), Felt252.fromInteger(5), Felt252.zero() };
    try std.testing.expectError(
        error.CantInvertZeroElement,
        Felt252.batchInv(&out, &in),
    );
}

test "Felt252 div" {
    const div_10_by_10 = try Felt252.fromInteger(10).div(Felt252.fromInteger(10));
    try std.testing.expect(
        div_10_by_10.isOne(),
    );
    try std.testing.expectError(
        error.DivisionByZero,
        Felt252.fromInteger(10).div(Felt252.zero()),
    );
}

test "Felt252 legendre" {
    try std.testing.expectEqual(
        Felt252.fromInteger(0x1000000000000022000000000000000000000000000000000000000000000002).legendre(),
        0,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(10).legendre(),
        1,
    );
    try std.testing.expectEqual(
        Felt252.fromInteger(135).legendre(),
        -1,
    );
}
