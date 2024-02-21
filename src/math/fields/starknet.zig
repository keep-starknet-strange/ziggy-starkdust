// Core imports.
const std = @import("std");
// Local imports.
const fields = @import("fields.zig");
const STARKNET_PRIME = @import("./constants.zig").STARKNET_PRIME;
const FELT_BYTE_SIZE = @import("./constants.zig").FELT_BYTE_SIZE;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// Base field for the Stark curve.
// The prime is 0x800000000000011000000000000000000000000000000000000000000000001.
pub const Felt252 = fields.Field(
    @import("stark_felt_252_gen_fp.zig"),
    STARKNET_PRIME,
);

pub const PRIME_STR = "0x800000000000011000000000000000000000000000000000000000000000001";

test "Felt252: fromU8 should return a field element from a u8" {
    try expectEqual(
        @as(u256, std.math.maxInt(u8)),
        Felt252.fromInt(u8, std.math.maxInt(u8)).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u8) / 3 * 2),
        Felt252.fromInt(u8, std.math.maxInt(u8) / 3 * 2).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u8) / 3),
        Felt252.fromInt(u8, std.math.maxInt(u8) / 3).toInteger(),
    );
}

test "Felt252: fromU16 should return a field element from a u16" {
    try expectEqual(
        @as(u256, std.math.maxInt(u16)),
        Felt252.fromInt(u16, std.math.maxInt(u16)).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u16) / 3 * 2),
        Felt252.fromInt(u16, std.math.maxInt(u16) / 3 * 2).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u16) / 3),
        Felt252.fromInt(u16, std.math.maxInt(u16) / 3).toInteger(),
    );
}

test "Felt252: fromU32 should return a field element from a u32" {
    try expectEqual(
        @as(u256, std.math.maxInt(u32)),
        Felt252.fromInt(u32, std.math.maxInt(u32)).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u32) / 3 * 2),
        Felt252.fromInt(u32, std.math.maxInt(u32) / 3 * 2).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u32) / 3),
        Felt252.fromInt(u32, std.math.maxInt(u32) / 3).toInteger(),
    );
}

test "Felt252: fromU64 should return a field element from a u64" {
    try expectEqual(
        @as(u256, std.math.maxInt(u64)),
        Felt252.fromInt(u64, std.math.maxInt(u64)).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u64) / 3 * 2),
        Felt252.fromInt(u64, std.math.maxInt(u64) / 3 * 2).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u64) / 3),
        Felt252.fromInt(u64, std.math.maxInt(u64) / 3).toInteger(),
    );
}

test "Felt252: fromUsize should return a field element from a usize" {
    try expectEqual(
        @as(u256, std.math.maxInt(usize)),
        Felt252.fromInt(usize, std.math.maxInt(usize)).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(usize) / 3 * 2),
        Felt252.fromInt(usize, std.math.maxInt(usize) / 3 * 2).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(usize) / 3),
        Felt252.fromInt(usize, std.math.maxInt(usize) / 3).toInteger(),
    );
}

test "Felt252: fromU128 should return a field element from a u128" {
    try expectEqual(
        @as(u256, std.math.maxInt(u128)),
        Felt252.fromInt(u128, std.math.maxInt(u128)).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u128) / 3 * 2),
        Felt252.fromInt(u128, std.math.maxInt(u128) / 3 * 2).toInteger(),
    );
    try expectEqual(
        @as(u256, std.math.maxInt(u128) / 3),
        Felt252.fromInt(u128, std.math.maxInt(u128) / 3).toInteger(),
    );
}

test "Felt252 testing for field numBits()" {
    try expectEqual(@as(u64, 1), Felt252.fromInt(u8, 1).numBits());
    try expectEqual(@as(u64, 4), Felt252.fromInt(u8, 10).numBits());
    try expectEqual(@as(u64, 252), Felt252.fromInt(u8, 1).neg().numBits());
    try expectEqual(@as(u64, 0), Felt252.fromInt(u8, 0).numBits());
}

test "Felt252 fromInteger" {
    try expectEqual(
        Felt252{ .fe = .{
            0xfffffffffffffec1,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0x7ffffffffffead0,
        } },
        Felt252.fromInt(u8, 10),
    );
    try expectEqual(
        Felt252{ .fe = .{
            0xfffffd737e000421,
            0x1330fffff,
            0xffffffffff6f8000,
            0x7ffd4ab5e008a30,
        } },
        Felt252.fromInt(u256, std.math.maxInt(u256)),
    );
}

test "Felt252 toInteger" {
    try expectEqual(
        @as(
            u256,
            10,
        ),
        Felt252.fromInt(u8, 10).toInteger(),
    );

    try expectEqual(
        @as(
            u256,
            0x7fffffffffffdf0ffffffffffffffffffffffffffffffffffffffffffffffe0,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).toInteger(),
    );
}

test "Felt252 one" {
    try expectEqual(
        Felt252{ .fe = .{
            0xffffffffffffffe1,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0x7fffffffffffdf0,
        } },
        Felt252.one(),
    );
}

test "Felt252 zero" {
    try expectEqual(
        Felt252{ .fe = .{
            0,
            0,
            0,
            0,
        } },
        Felt252.zero(),
    );
}

test "Felt252 equal" {
    try expect(Felt252.zero().equal(Felt252.zero()));
    try expect(Felt252.fromInt(u8, 10).equal(Felt252.fromInt(u8, 10)));
    try expect(!Felt252.fromInt(u8, 100).equal(Felt252.fromInt(u8, 10)));
}

test "Felt252 isZero" {
    try expect(Felt252.zero().isZero());
    try expect(!Felt252.one().isZero());
    try expect(!Felt252.fromInt(u8, 10).isZero());
}

test "Felt252 isOne" {
    try expect(Felt252.one().isOne());
    try expect(!Felt252.zero().isOne());
    try expect(!Felt252.fromInt(u8, 10).isOne());
}

test "Felt252 fromBytes" {
    const a: [FELT_BYTE_SIZE]u8 = .{
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
    try expectEqual(
        @as(
            u256,
            0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e,
        ),
        Felt252.fromBytes(a).toInteger(),
    );

    try expectEqual(
        Felt252.fromInt(u256, 0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e),
        Felt252.fromBytes(a),
    );
}

test "Felt252 toBytes" {
    const expected = [_]u8{
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
    try expectEqual(
        expected,
        Felt252.fromInt(u256, 0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e).toBytes(),
    );
}

test "Felt252 tryIntoU64" {
    try expectEqual(
        @as(
            u64,
            10,
        ),
        try Felt252.fromInt(u8, 10).tryIntoU64(),
    );
    try expectEqual(
        @as(
            u64,
            std.math.maxInt(u64),
        ),
        try Felt252.fromInt(u64, std.math.maxInt(u64)).tryIntoU64(),
    );
    try std.testing.expectError(
        error.ValueTooLarge,
        Felt252.fromInt(u128, std.math.maxInt(u64) + 1).tryIntoU64(),
    );
}

test "Felt252 arithmetic operations" {
    const a = Felt252.one();
    const b = Felt252.two();
    const c = a.add(b);
    try expect(c.equal(Felt252.three()));
}

test "Felt252 add" {
    try expectEqual(
        @as(
            u256,
            0xf,
        ),
        Felt252.fromInt(u8, 10).add(Felt252.fromInt(u8, 5)).toInteger(),
    );
    try expect(Felt252.one().add(Felt252.zero()).isOne());
    try expect(Felt252.zero().add(Felt252.zero()).isZero());
    try expectEqual(
        @as(
            u256,
            0x7fffffffffffbd0ffffffffffffffffffffffffffffffffffffffffffffffbf,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).add(Felt252.fromInt(u256, std.math.maxInt(u256))).toInteger(),
    );
}

test "Felt252 sub" {
    try expectEqual(
        @as(
            u256,
            0x5,
        ),
        Felt252.fromInt(u8, 10).sub(Felt252.fromInt(u8, 5)).toInteger(),
    );
    try expect(Felt252.fromInt(u256, std.math.maxInt(u256)).sub(Felt252.fromInt(u256, std.math.maxInt(u256))).isZero());
    try expect(Felt252.zero().sub(Felt252.zero()).isZero());
}

test "Felt252 mul" {
    try expect(Felt252.zero().mul(Felt252.zero()).isZero());
    try expect(Felt252.one().mul(Felt252.one()).isOne());
    try expectEqual(
        @as(
            u256,
            0x32,
        ),
        Felt252.fromInt(u8, 10).mul(Felt252.fromInt(u8, 5)).toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x7fffffffffffbd0ffffffffffffffffffffffffffffffffffffffffffffffbf,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).mul(Felt252.two()).toInteger(),
    );
}

test "Felt252 mulBy5" {
    try expect(Felt252.zero().mulBy5().isZero());
    try expectEqual(
        @as(
            u256,
            5,
        ),
        Felt252.one().mulBy5().toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x7fffffffffff570ffffffffffffffffffffffffffffffffffffffffffffff5c,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).mulBy5().toInteger(),
    );
}

test "Felt252 neg" {
    try expectEqual(
        @as(
            u256,
            0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffff7,
        ),
        Felt252.fromInt(u8, 10).neg().toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x220000000000000000000000000000000000000000000000021,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).neg().toInteger(),
    );
}

test "Felt252 square" {
    try expectEqual(
        @as(
            u256,
            0x64,
        ),
        Felt252.fromInt(u8, 10).square().toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x7ffd4ab5e008c50ffffffffff6f800000000001330ffffffffffd737e000442,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).square().toInteger(),
    );
}

test "Felt252 pow2" {
    try expectEqual(
        @as(
            u256,
            0x4cdffe7c7b3f76a6ce28dde767fa09b60e963927bbd16d8b0d3a0fc13c6fa0,
        ),
        Felt252.fromInt(u8, 10).pow2(10).toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x25f7dc4108a227e91fb20740a4866274f449e9d427775a58bb7cb4eaff1e653,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).pow2(3).toInteger(),
    );
}

test "Felt252 pow" {
    try expectEqual(
        @as(
            u256,
            0x2540be400,
        ),
        Felt252.fromInt(u8, 10).pow(10).toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x48ea9fffffffffffffff5ffffffffffffffe5000000000000449f,
        ),
        Felt252.fromInt(u64, std.math.maxInt(u64)).pow(5).toInteger(),
    );
}

test "Felt252 inv" {
    try expectEqual(
        @as(
            u256,
            0x733333333333342800000000000000000000000000000000000000000000001,
        ),
        Felt252.fromInt(u8, 10).inv().?.toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x538bf4edb6bf78474ef0f1979a0db0bdd364ce7aeda9f3c6c04bea822682ba,
        ),
        Felt252.fromInt(u256, std.math.maxInt(u256)).inv().?.toInteger(),
    );
    try expectEqual(
        @as(
            ?Felt252,
            null,
        ),
        Felt252.zero().inv(),
    );
}

test "Felt252 batchInv" {
    var out: [2]Felt252 = undefined;
    const in: [2]Felt252 = .{ Felt252.fromInt(u8, 10), Felt252.fromInt(u8, 5) };
    try Felt252.batchInv(&out, &in);
    try expectEqual(
        @as(
            u256,
            0x733333333333342800000000000000000000000000000000000000000000001,
        ),
        out[0].toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x666666666666674000000000000000000000000000000000000000000000001,
        ),
        out[1].toInteger(),
    );
}

test "Felt252 batchInv with zero" {
    var out: [3]Felt252 = undefined;
    try std.testing.expectError(
        error.CantInvertZeroElement,
        Felt252.batchInv(&out, &.{ Felt252.fromInt(u8, 10), Felt252.fromInt(u8, 5), Felt252.zero() }),
    );
}

test "Felt252 div" {
    const div_10_by_10 = try Felt252.fromInt(u8, 10).div(Felt252.fromInt(u8, 10));
    try expect(
        div_10_by_10.isOne(),
    );
    try std.testing.expectError(
        error.DivisionByZero,
        Felt252.fromInt(u8, 10).div(Felt252.zero()),
    );
}

test "Felt252 legendre" {
    try expectEqual(
        @as(
            i2,
            0,
        ),
        Felt252.fromInt(u256, 0x1000000000000022000000000000000000000000000000000000000000000002).legendre(),
    );
    try expectEqual(
        @as(
            i2,
            1,
        ),
        Felt252.fromInt(u8, 10).legendre(),
    );
    try expectEqual(
        @as(
            i2,
            -1,
        ),
        Felt252.fromInt(u8, 135).legendre(),
    );
}

test "Felt252 cmp" {
    try expect(Felt252.fromInt(u8, 10).cmp(Felt252.fromInt(u64, 343535)) == .lt);
    try expect(Felt252.fromInt(u64, 433).cmp(Felt252.fromInt(u64, 343535)) == .lt);
    try expect(Felt252.fromInt(u64, 543636535).cmp(Felt252.fromInt(u64, 434)) == .gt);
    try expect(Felt252.fromInt(u256, std.math.maxInt(u256)).cmp(Felt252.fromInt(u64, 21313)) == .gt);
    try expect(Felt252.fromInt(u8, 10).cmp(Felt252.fromInt(u8, 10)) == .eq);
    try expect(Felt252.one().cmp(Felt252.one()) == .eq);
    try expect(Felt252.zero().cmp(Felt252.zero()) == .eq);
    try expect(Felt252.fromInt(u8, 10).cmp(Felt252.fromInt(u256, 10 + STARKNET_PRIME)) == .eq);
}

test "Felt252 lt" {
    try expect(Felt252.fromInt(u8, 10).lt(Felt252.fromInt(u64, 343535)));
    try expect(Felt252.fromInt(u64, 433).lt(Felt252.fromInt(u64, 343535)));
    try expect(!Felt252.fromInt(u64, 543636535).lt(Felt252.fromInt(u64, 434)));
    try expect(!Felt252.fromInt(u256, std.math.maxInt(u256)).lt(Felt252.fromInt(u64, 21313)));
    try expect(!Felt252.fromInt(u8, 10).lt(Felt252.fromInt(u8, 10)));
    try expect(!Felt252.one().lt(Felt252.one()));
    try expect(!Felt252.zero().lt(Felt252.zero()));
    try expect(!Felt252.fromInt(u8, 10).lt(
        Felt252.fromInt(u256, 10 + STARKNET_PRIME),
    ));
}

test "Felt252 le" {
    try expect(Felt252.fromInt(u8, 10).le(Felt252.fromInt(u64, 343535)));
    try expect(Felt252.fromInt(u64, 433).le(Felt252.fromInt(u64, 343535)));
    try expect(!Felt252.fromInt(u64, 543636535).le(Felt252.fromInt(u64, 434)));
    try expect(!Felt252.fromInt(u256, std.math.maxInt(u256)).le(Felt252.fromInt(u64, 21313)));
    try expect(Felt252.fromInt(u8, 10).le(Felt252.fromInt(u8, 10)));
    try expect(Felt252.one().le(Felt252.one()));
    try expect(Felt252.zero().le(Felt252.zero()));
    try expect(Felt252.fromInt(u8, 10).le(
        Felt252.fromInt(u256, 10 + STARKNET_PRIME),
    ));
}

test "Felt252 gt" {
    try expect(!Felt252.fromInt(u8, 10).gt(Felt252.fromInt(u64, 343535)));
    try expect(!Felt252.fromInt(u64, 433).gt(Felt252.fromInt(u64, 343535)));
    try expect(Felt252.fromInt(u64, 543636535).gt(Felt252.fromInt(u64, 434)));
    try expect(Felt252.fromInt(u256, std.math.maxInt(u256)).gt(Felt252.fromInt(u64, 21313)));
    try expect(!Felt252.fromInt(u8, 10).gt(Felt252.fromInt(u8, 10)));
    try expect(!Felt252.one().gt(Felt252.one()));
    try expect(!Felt252.zero().gt(Felt252.zero()));
    try expect(!Felt252.fromInt(u8, 10).gt(
        Felt252.fromInt(u256, 10 + STARKNET_PRIME),
    ));
}

test "Felt252 ge" {
    try expect(!Felt252.fromInt(u8, 10).ge(Felt252.fromInt(u64, 343535)));
    try expect(!Felt252.fromInt(u64, 433).ge(Felt252.fromInt(u64, 343535)));
    try expect(Felt252.fromInt(u64, 543636535).ge(Felt252.fromInt(u64, 434)));
    try expect(Felt252.fromInt(u256, std.math.maxInt(u256)).ge(Felt252.fromInt(u64, 21313)));
    try expect(Felt252.fromInt(u8, 10).ge(Felt252.fromInt(u8, 10)));
    try expect(Felt252.one().ge(Felt252.one()));
    try expect(Felt252.zero().ge(Felt252.zero()));
    try expect(Felt252.fromInt(u8, 10).ge(
        Felt252.fromInt(u256, 10 + STARKNET_PRIME),
    ));
}

test "Felt252 lexographicallyLargest" {
    try expect(!Felt252.zero().lexographicallyLargest());
    try expect(!Felt252.fromInt(
        u256,
        0x400000000000008800000000000000000000000000000000000000000000000,
    ).lexographicallyLargest());
    try expect(!Felt252.fromInt(
        u256,
        0x4000000000000087fffffffffffffffffffffffffffffffffffffffffffffff,
    ).lexographicallyLargest());
    try expect(Felt252.fromInt(
        u256,
        0x400000000000008800000000000000000000000000000000000000000000001,
    ).lexographicallyLargest());
    try expect(Felt252.fromInt(u256, std.math.maxInt(u256)).lexographicallyLargest());
}

test "Felt252 overflowing_shl" {
    var a = Felt252.fromInt(u8, 10);
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0xfffffffffffffd82,
                    0xffffffffffffffff,
                    0xffffffffffffffff,
                    0xfffffffffffd5a1,
                } },
                false,
            },
        ),
        a.overflowing_shl(1),
    );
    var b = Felt252.fromInt(u256, std.math.maxInt(u256));
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0xffffae6fc0008420,
                    0x2661ffffff,
                    0xffffffffedf00000,
                    0xfffa956bc011461f,
                } },
                false,
            },
        ),
        b.overflowing_shl(5),
    );
    var c = Felt252.fromInt(u64, 44444444);
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0xfffffeacea720400, 0xffffffffffffffff, 0xffffffffffffffff, 0xffffe97b919243ff,
                } },
                true,
            },
        ),
        c.overflowing_shl(10),
    );
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252.zero(),
                true,
            },
        ),
        c.overflowing_shl(5 * 64),
    );
    var d = Felt252.fromInt(u64, 33333333);
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{ 0x0, 0x0, 0x0, 0xffffffffc06bf561 } },
                true,
            },
        ),
        d.overflowing_shl(3 * 64),
    );
}

test "Felt252 wrapping_shl" {
    var a = Felt252.fromInt(u8, 10);
    try expectEqual(
        Felt252{ .fe = .{
            0xfffffffffffffd82,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0xfffffffffffd5a1,
        } },
        a.wrapping_shl(1),
    );
    var b = Felt252.fromInt(u256, std.math.maxInt(u256));
    try expectEqual(
        Felt252{ .fe = .{
            0xffffae6fc0008420,
            0x2661ffffff,
            0xffffffffedf00000,
            0xfffa956bc011461f,
        } },
        b.wrapping_shl(5),
    );
    var c = Felt252.fromInt(u64, 44444444);
    try expectEqual(
        Felt252{ .fe = .{
            0xfffffeacea720400, 0xffffffffffffffff, 0xffffffffffffffff, 0xffffe97b919243ff,
        } },
        c.wrapping_shl(10),
    );
    try expectEqual(
        Felt252.zero(),
        c.wrapping_shl(5 * 64),
    );
    var d = Felt252.fromInt(u64, 33333333);
    try expectEqual(
        Felt252{ .fe = .{ 0x0, 0x0, 0x0, 0xffffffffc06bf561 } },
        d.wrapping_shl(3 * 64),
    );
}

test "Felt252 saturating_shl" {
    var a = Felt252.fromInt(u8, 10);
    try expectEqual(
        Felt252{ .fe = .{
            0xfffffffffffffd82,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0xfffffffffffd5a1,
        } },
        a.saturating_shl(1),
    );
    var b = Felt252.fromInt(u256, std.math.maxInt(u256));
    try expectEqual(
        Felt252{ .fe = .{
            0xffffae6fc0008420,
            0x2661ffffff,
            0xffffffffedf00000,
            0xfffa956bc011461f,
        } },
        b.saturating_shl(5),
    );
    var c = Felt252.fromInt(u64, 44444444);
    try expectEqual(
        Felt252{ .fe = .{
            std.math.maxInt(u64),
            std.math.maxInt(u64),
            std.math.maxInt(u64),
            std.math.maxInt(u64),
        } },
        c.saturating_shl(10),
    );
    try expectEqual(
        Felt252{ .fe = .{
            std.math.maxInt(u64),
            std.math.maxInt(u64),
            std.math.maxInt(u64),
            std.math.maxInt(u64),
        } },
        c.saturating_shl(5 * 64),
    );
    var d = Felt252.fromInt(u64, 33333333);
    try expectEqual(
        Felt252{ .fe = .{
            std.math.maxInt(u64),
            std.math.maxInt(u64),
            std.math.maxInt(u64),
            std.math.maxInt(u64),
        } },
        d.saturating_shl(3 * 64),
    );
}

test "Felt252 checked_shl" {
    var a = Felt252.fromInt(u8, 10);
    try expectEqual(
        Felt252{ .fe = .{
            0xfffffffffffffd82,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0xfffffffffffd5a1,
        } },
        a.checked_shl(1).?,
    );
    var b = Felt252.fromInt(u256, std.math.maxInt(u256));
    try expectEqual(
        Felt252{ .fe = .{
            0xffffae6fc0008420,
            0x2661ffffff,
            0xffffffffedf00000,
            0xfffa956bc011461f,
        } },
        b.checked_shl(5).?,
    );
    var c = Felt252.fromInt(u64, 44444444);
    try expectEqual(
        @as(?Felt252, null),
        c.checked_shl(10),
    );
    try expectEqual(
        @as(?Felt252, null),
        c.checked_shl(5 * 64),
    );
    var d = Felt252.fromInt(u64, 33333333);
    try expectEqual(
        @as(?Felt252, null),
        d.checked_shl(3 * 64),
    );
}

test "Felt252 overflowing_shr" {
    var a = Felt252.fromInt(u8, 10);
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0xffffffffffffff60,
                    0xffffffffffffffff,
                    0x7fffffffffffffff,
                    0x3fffffffffff568,
                } },
                true,
            },
        ),
        a.overflowing_shr(1),
    );
    var b = Felt252.fromInt(u256, std.math.maxInt(u256));
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0xffffffeb9bf00021, 0x9987fff, 0x87fffffffffb7c00, 0x3ffea55af00451,
                } },
                true,
            },
        ),
        b.overflowing_shr(5),
    );
    var c = Felt252.fromInt(u64, 44444444);
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0xffffffffffeacea7, 0xffffffffffffffff, 0x243fffffffffffff, 0x1fffffe97b919,
                } },
                true,
            },
        ),
        c.overflowing_shr(10),
    );
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252.zero(),
                true,
            },
        ),
        c.overflowing_shr(5 * 64),
    );
    var d = Felt252.fromInt(u64, 33333333);
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0x7fffffbc72b4b70,
                    0x0,
                    0x0,
                    0x0,
                } },
                true,
            },
        ),
        d.overflowing_shr(3 * 64),
    );
    var e = Felt252{ .fe = .{
        0x0,
        0xffffffffffffffff,
        0xffffffffffffffff,
        0x0,
    } };
    try expectEqual(
        @as(
            std.meta.Tuple(&.{ Felt252, bool }),
            .{
                Felt252{ .fe = .{
                    0x8000000000000000, 0xffffffffffffffff, 0x7fffffffffffffff, 0x0,
                } },
                false,
            },
        ),
        e.overflowing_shr(1),
    );
}

test "Felt252 checked_shr" {
    var a = Felt252.fromInt(u8, 10);
    try expectEqual(
        @as(?Felt252, null),
        a.checked_shr(1),
    );
    var b = Felt252.fromInt(u256, std.math.maxInt(u256));
    try expectEqual(
        @as(?Felt252, null),
        b.checked_shr(5),
    );
    var c = Felt252.fromInt(u64, 44444444);
    try expectEqual(
        @as(?Felt252, null),
        c.checked_shr(10),
    );
    try expectEqual(
        @as(?Felt252, null),
        c.checked_shr(5 * 64),
    );
    var d = Felt252.fromInt(u64, 33333333);
    try expectEqual(
        @as(?Felt252, null),
        d.checked_shr(3 * 64),
    );
    var e = Felt252{ .fe = .{
        0x0,
        0xffffffffffffffff,
        0xffffffffffffffff,
        0x0,
    } };
    try expectEqual(
        Felt252{ .fe = .{
            0x8000000000000000, 0xffffffffffffffff, 0x7fffffffffffffff, 0x0,
        } },
        e.checked_shr(1).?,
    );
}

test "Felt252 wrapping_shr" {
    var a = Felt252.fromInt(u8, 10);
    try expectEqual(
        Felt252{ .fe = .{
            0xffffffffffffff60,
            0xffffffffffffffff,
            0x7fffffffffffffff,
            0x3fffffffffff568,
        } },
        a.wrapping_shr(1),
    );
    var b = Felt252.fromInt(u256, std.math.maxInt(u256));
    try expectEqual(
        Felt252{ .fe = .{
            0xffffffeb9bf00021, 0x9987fff, 0x87fffffffffb7c00, 0x3ffea55af00451,
        } },
        b.wrapping_shr(5),
    );
    var c = Felt252.fromInt(u64, 44444444);
    try expectEqual(
        Felt252{ .fe = .{
            0xffffffffffeacea7, 0xffffffffffffffff, 0x243fffffffffffff, 0x1fffffe97b919,
        } },
        c.wrapping_shr(10),
    );
    try expectEqual(
        Felt252.zero(),
        c.wrapping_shr(5 * 64),
    );
    var d = Felt252.fromInt(u64, 33333333);
    try expectEqual(
        Felt252{ .fe = .{
            0x7fffffbc72b4b70,
            0x0,
            0x0,
            0x0,
        } },
        d.wrapping_shr(3 * 64),
    );
    var e = Felt252{ .fe = .{
        0x0,
        0xffffffffffffffff,
        0xffffffffffffffff,
        0x0,
    } };
    try expectEqual(
        Felt252{ .fe = .{
            0x8000000000000000, 0xffffffffffffffff, 0x7fffffffffffffff, 0x0,
        } },
        e.wrapping_shr(1),
    );
}

test "Felt252: fromSigned and toSigned" {
    try expectEqual(Felt252.zero().sub(Felt252.one()), Felt252.fromSignedInt(-1));

    try expectEqual(Felt252.fromInt(u32, 250), Felt252.fromSignedInt(-250).neg());

    try expectEqual(Felt252.fromInt(u256, std.math.maxInt(i256)), Felt252.fromSignedInt(std.math.maxInt(i256)));

    const maxSignedNeg = Felt252.fromSignedInt(-std.math.maxInt(i256) + 1).toSignedInt();
    // because overflow its positive number
    try expectEqual(
        true,
        maxSignedNeg > 0,
    );
}
