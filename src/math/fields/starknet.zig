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

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Felt252 fromInteger" {
    try expectEqual(
        Felt252{ .fe = .{
            0xfffffffffffffec1,
            0xffffffffffffffff,
            0xffffffffffffffff,
            0x7ffffffffffead0,
        } },
        Felt252.fromInteger(10),
    );

    try expectEqual(
        Felt252{ .fe = .{
            0xfffffd737e000421,
            0x1330fffff,
            0xffffffffff6f8000,
            0x7ffd4ab5e008a30,
        } },
        Felt252.fromInteger(std.math.maxInt(u256)),
    );
}

test "Felt252 toInteger" {
    try expectEqual(
        @as(
            u256,
            10,
        ),
        Felt252.fromInteger(10).toInteger(),
    );

    try expectEqual(
        @as(
            u256,
            0x7fffffffffffdf0ffffffffffffffffffffffffffffffffffffffffffffffe0,
        ),
        Felt252.fromInteger(std.math.maxInt(u256)).toInteger(),
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
    try expect(Felt252.fromInteger(10).equal(Felt252.fromInteger(10)));
    try expect(!Felt252.fromInteger(100).equal(Felt252.fromInteger(10)));
}

test "Felt252 isZero" {
    try expect(Felt252.zero().isZero());
    try expect(!Felt252.one().isZero());
    try expect(!Felt252.fromInteger(10).isZero());
}

test "Felt252 isOne" {
    try expect(Felt252.one().isOne());
    try expect(!Felt252.zero().isOne());
    try expect(!Felt252.fromInteger(10).isOne());
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
    try expectEqual(
        @as(
            u256,
            0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e,
        ),
        Felt252.fromBytes(a).toInteger(),
    );

    try expectEqual(
        Felt252.fromInteger(0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e),
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
        Felt252.fromInteger(0x96f8e63ba9b2bcea770f6a07c669ba51ce76df2f67195f5f5f5f5f5f5f5f4e).toBytes(),
    );
}

test "Felt252 tryIntoU64" {
    try expectEqual(
        @as(
            u64,
            10,
        ),
        try Felt252.fromInteger(10).tryIntoU64(),
    );
    try expectEqual(
        @as(
            u64,
            std.math.maxInt(u64),
        ),
        try Felt252.fromInteger(std.math.maxInt(u64)).tryIntoU64(),
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
    try expect(c.equal(Felt252.fromInteger(3)));
}

test "Felt252 add" {
    try expectEqual(
        @as(
            u256,
            0xf,
        ),
        Felt252.fromInteger(10).add(Felt252.fromInteger(5)).toInteger(),
    );
    try expect(Felt252.one().add(Felt252.zero()).isOne());
    try expect(Felt252.zero().add(Felt252.zero()).isZero());
    try expectEqual(
        @as(
            u256,
            0x7fffffffffffbd0ffffffffffffffffffffffffffffffffffffffffffffffbf,
        ),
        Felt252.fromInteger(std.math.maxInt(u256)).add(Felt252.fromInteger(std.math.maxInt(u256))).toInteger(),
    );
}

test "Felt252 sub" {
    try expectEqual(
        @as(
            u256,
            0x5,
        ),
        Felt252.fromInteger(10).sub(Felt252.fromInteger(5)).toInteger(),
    );
    try expect(Felt252.fromInteger(std.math.maxInt(u256)).sub(Felt252.fromInteger(std.math.maxInt(u256))).isZero());
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
        Felt252.fromInteger(10).mul(Felt252.fromInteger(5)).toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x7fffffffffffbd0ffffffffffffffffffffffffffffffffffffffffffffffbf,
        ),
        Felt252.fromInteger(std.math.maxInt(u256)).mul(Felt252.fromInteger(2)).toInteger(),
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
        Felt252.fromInteger(std.math.maxInt(u256)).mulBy5().toInteger(),
    );
}

test "Felt252 neg" {
    try expectEqual(
        @as(
            u256,
            0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffff7,
        ),
        Felt252.fromInteger(10).neg().toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x220000000000000000000000000000000000000000000000021,
        ),
        Felt252.fromInteger(std.math.maxInt(u256)).neg().toInteger(),
    );
}

test "Felt252 square" {
    try expectEqual(
        @as(
            u256,
            0x64,
        ),
        Felt252.fromInteger(10).square().toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x7ffd4ab5e008c50ffffffffff6f800000000001330ffffffffffd737e000442,
        ),
        Felt252.fromInteger(std.math.maxInt(u256)).square().toInteger(),
    );
}

test "Felt252 pow2" {
    try expectEqual(
        @as(
            u256,
            0x4cdffe7c7b3f76a6ce28dde767fa09b60e963927bbd16d8b0d3a0fc13c6fa0,
        ),
        Felt252.fromInteger(10).pow2(10).toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x25f7dc4108a227e91fb20740a4866274f449e9d427775a58bb7cb4eaff1e653,
        ),
        Felt252.fromInteger(std.math.maxInt(u256)).pow2(3).toInteger(),
    );
}

test "Felt252 pow" {
    try expectEqual(
        @as(
            u256,
            0x2540be400,
        ),
        Felt252.fromInteger(10).pow(10).toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x48ea9fffffffffffffff5ffffffffffffffe5000000000000449f,
        ),
        Felt252.fromInteger(std.math.maxInt(u64)).pow(5).toInteger(),
    );
}

test "Felt252 inv" {
    try expectEqual(
        @as(
            u256,
            0x733333333333342800000000000000000000000000000000000000000000001,
        ),
        Felt252.fromInteger(10).inv().?.toInteger(),
    );
    try expectEqual(
        @as(
            u256,
            0x538bf4edb6bf78474ef0f1979a0db0bdd364ce7aeda9f3c6c04bea822682ba,
        ),
        Felt252.fromInteger(std.math.maxInt(u256)).inv().?.toInteger(),
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
    const in: [2]Felt252 = .{ Felt252.fromInteger(10), Felt252.fromInteger(5) };
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
    const in: [3]Felt252 = .{ Felt252.fromInteger(10), Felt252.fromInteger(5), Felt252.zero() };
    try std.testing.expectError(
        error.CantInvertZeroElement,
        Felt252.batchInv(&out, &in),
    );
}

test "Felt252 div" {
    const div_10_by_10 = try Felt252.fromInteger(10).div(Felt252.fromInteger(10));
    try expect(
        div_10_by_10.isOne(),
    );
    try std.testing.expectError(
        error.DivisionByZero,
        Felt252.fromInteger(10).div(Felt252.zero()),
    );
}

test "Felt252 legendre" {
    try expectEqual(
        @as(
            i2,
            0,
        ),
        Felt252.fromInteger(0x1000000000000022000000000000000000000000000000000000000000000002).legendre(),
    );
    try expectEqual(
        @as(
            i2,
            1,
        ),
        Felt252.fromInteger(10).legendre(),
    );
    try expectEqual(
        @as(
            i2,
            -1,
        ),
        Felt252.fromInteger(135).legendre(),
    );
}

test "Felt252 cmp" {
    try expect(Felt252.fromInteger(10).cmp(
        Felt252.fromInteger(343535),
    ) == .gt);
    try expect(Felt252.fromInteger(433).cmp(
        Felt252.fromInteger(343535),
    ) == .gt);
    try expect(Felt252.fromInteger(543636535).cmp(
        Felt252.fromInteger(434),
    ) == .lt);
    try expect(Felt252.fromInteger(std.math.maxInt(u256)).cmp(
        Felt252.fromInteger(21313),
    ) == .lt);
    try expect(Felt252.fromInteger(10).cmp(
        Felt252.fromInteger(10),
    ) == .eq);
    try expect(Felt252.one().cmp(
        Felt252.one(),
    ) == .eq);
    try expect(Felt252.zero().cmp(
        Felt252.zero(),
    ) == .eq);
    try expect(Felt252.fromInteger(10).cmp(
        Felt252.fromInteger(10 + 0x800000000000011000000000000000000000000000000000000000000000001),
    ) == .eq);
}

test "Felt252 lt" {
    try expect(!Felt252.fromInteger(10).lt(Felt252.fromInteger(343535)));
    try expect(!Felt252.fromInteger(433).lt(Felt252.fromInteger(343535)));
    try expect(Felt252.fromInteger(543636535).lt(Felt252.fromInteger(434)));
    try expect(Felt252.fromInteger(std.math.maxInt(u256)).lt(Felt252.fromInteger(21313)));
    try expect(!Felt252.fromInteger(10).lt(Felt252.fromInteger(10)));
    try expect(!Felt252.one().lt(Felt252.one()));
    try expect(!Felt252.zero().lt(Felt252.zero()));
    try expect(!Felt252.fromInteger(10).lt(
        Felt252.fromInteger(10 + 0x800000000000011000000000000000000000000000000000000000000000001),
    ));
}

test "Felt252 le" {
    try expect(!Felt252.fromInteger(10).le(Felt252.fromInteger(343535)));
    try expect(!Felt252.fromInteger(433).le(Felt252.fromInteger(343535)));
    try expect(Felt252.fromInteger(543636535).le(Felt252.fromInteger(434)));
    try expect(Felt252.fromInteger(std.math.maxInt(u256)).le(Felt252.fromInteger(21313)));
    try expect(Felt252.fromInteger(10).le(Felt252.fromInteger(10)));
    try expect(Felt252.one().le(Felt252.one()));
    try expect(Felt252.zero().le(Felt252.zero()));
    try expect(Felt252.fromInteger(10).le(
        Felt252.fromInteger(10 + 0x800000000000011000000000000000000000000000000000000000000000001),
    ));
}

test "Felt252 gt" {
    try expect(Felt252.fromInteger(10).gt(Felt252.fromInteger(343535)));
    try expect(Felt252.fromInteger(433).gt(Felt252.fromInteger(343535)));
    try expect(!Felt252.fromInteger(543636535).gt(Felt252.fromInteger(434)));
    try expect(!Felt252.fromInteger(std.math.maxInt(u256)).gt(Felt252.fromInteger(21313)));
    try expect(!Felt252.fromInteger(10).gt(Felt252.fromInteger(10)));
    try expect(!Felt252.one().gt(Felt252.one()));
    try expect(!Felt252.zero().gt(Felt252.zero()));
    try expect(!Felt252.fromInteger(10).gt(
        Felt252.fromInteger(10 + 0x800000000000011000000000000000000000000000000000000000000000001),
    ));
}

test "Felt252 ge" {
    try expect(Felt252.fromInteger(10).ge(Felt252.fromInteger(343535)));
    try expect(Felt252.fromInteger(433).ge(Felt252.fromInteger(343535)));
    try expect(!Felt252.fromInteger(543636535).ge(Felt252.fromInteger(434)));
    try expect(!Felt252.fromInteger(std.math.maxInt(u256)).ge(Felt252.fromInteger(21313)));
    try expect(Felt252.fromInteger(10).ge(Felt252.fromInteger(10)));
    try expect(Felt252.one().ge(Felt252.one()));
    try expect(Felt252.zero().ge(Felt252.zero()));
    try expect(Felt252.fromInteger(10).ge(
        Felt252.fromInteger(10 + 0x800000000000011000000000000000000000000000000000000000000000001),
    ));
}

test "Felt252 lexographicallyLargest" {
    try expect(!Felt252.fromInteger(0).lexographicallyLargest());
    try expect(!Felt252.fromInteger(
        0x400000000000008800000000000000000000000000000000000000000000000,
    ).lexographicallyLargest());
    try expect(!Felt252.fromInteger(
        0x4000000000000087fffffffffffffffffffffffffffffffffffffffffffffff,
    ).lexographicallyLargest());
    try expect(Felt252.fromInteger(
        0x400000000000008800000000000000000000000000000000000000000000001,
    ).lexographicallyLargest());
    try expect(Felt252.fromInteger(std.math.maxInt(u256)).lexographicallyLargest());
}
