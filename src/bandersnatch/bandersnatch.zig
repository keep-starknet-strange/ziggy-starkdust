const std = @import("std");
const BandersnatchFields = @import("../fields/fields.zig").BandersnatchFields;
const extendedpoints = @import("points/extended.zig");

// Bandersnatch base and scalar finite fields.
pub const Fp = BandersnatchFields.BaseField;
pub const Fr = BandersnatchFields.ScalarField;

// Curve parameters.
pub const A = Fp.fromInteger(Fp.Modulo - 5);
pub const D = Fp.fromInteger(138827208126141220649022263972958607803).div(Fp.fromInteger(171449701953573178309673572579671231137)) catch unreachable;

// Points.
pub const AffinePoint = @import("points/affine.zig");
pub const ExtendedPoint = extendedpoints.ExtendedPoint;
pub const ExtendedPointMSM = extendedpoints.ExtendedPointMSM;

// Errors
pub const CurveError = error{
    NotInCurve,
};

test "addition" {
    const gen = ExtendedPoint.generator();
    const result_add = gen.add(gen);

    var result_double = ExtendedPoint.identity();
    result_double = gen.double();

    try std.testing.expect(result_add.equal(result_double));
}

test "equality" {
    const gen = ExtendedPoint.generator();
    const neg_gen = gen.neg();

    try std.testing.expect(gen.equal(gen));
    try std.testing.expect(!gen.equal(neg_gen));
}

test "neg" {
    const gen = ExtendedPoint.generator();
    const expected = ExtendedPoint.identity();

    const neg_gen = gen.neg();
    const result = neg_gen.add(gen);

    try std.testing.expect(expected.equal(result));
}

test "serialize gen" {
    const gen = ExtendedPoint.generator();
    const serialised_point = gen.toBytes();

    // test vector taken from the rust code (see spec reference)
    const expected = "18ae52a26618e7e1658499ad22c0792bf342be7b77113774c5340b2ccc32c129";
    const actual = std.fmt.bytesToHex(&serialised_point, std.fmt.Case.lower);
    try std.testing.expectEqualSlices(u8, expected, &actual);
}

test "scalar mul smoke" {
    const gen = ExtendedPoint.generator();

    const scalar = Fr.fromInteger(2);
    const result = gen.scalarMul(scalar);

    const twoG = ExtendedPoint.generator().double();

    try std.testing.expect(twoG.equal(result));
}

test "scalar mul minus one" {
    const gen = ExtendedPoint.generator();

    const integer = Fr.Modulo - 1;

    const scalar = Fr.fromInteger(integer);
    const result = gen.scalarMul(scalar);

    const expected = "e951ad5d98e7181e99d76452e0e343281295e38d90c602bf824892fd86742c4a";
    const actual = std.fmt.bytesToHex(result.toBytes(), std.fmt.Case.lower);
    try std.testing.expectEqualSlices(u8, expected, &actual);
}

test "one" {
    const oneFromInteger = Fp.fromInteger(1);
    const oneFromAPI = Fp.one();

    try std.testing.expect(oneFromInteger.equal(oneFromAPI));
}

test "zero" {
    const zeroFromInteger = Fp.fromInteger(0);
    const zeroFromAPI = Fp.zero();

    try std.testing.expect(zeroFromInteger.equal(zeroFromAPI));
}

test "lexographically largest" {
    try std.testing.expect(!Fp.fromInteger(0).lexographicallyLargest());
    try std.testing.expect(!Fp.fromInteger(Fp.QMinOneDiv2).lexographicallyLargest());

    try std.testing.expect(Fp.fromInteger(Fp.QMinOneDiv2 + 1).lexographicallyLargest());
    try std.testing.expect(Fp.fromInteger(Fp.Modulo - 1).lexographicallyLargest());
}

test "from and to bytes" {
    const cases = [_]Fp{ Fp.fromInteger(0), Fp.fromInteger(1), Fp.fromInteger(Fp.QMinOneDiv2), Fp.fromInteger(Fp.Modulo - 1) };

    for (cases) |fe| {
        const bytes = fe.toBytes();
        const fe2 = Fp.fromBytes(bytes);
        try std.testing.expect(fe.equal(fe2));

        const bytes2 = fe2.toBytes();
        try std.testing.expectEqualSlices(u8, &bytes, &bytes2);
    }
}

test "to integer" {
    try std.testing.expect(Fp.fromInteger(0).toInteger() == 0);
    try std.testing.expect(Fp.fromInteger(1).toInteger() == 1);
    try std.testing.expect(Fp.fromInteger(100).toInteger() == 100);
}

test "add sub mul neg" {
    const got = Fp.fromInteger(10).mul(Fp.fromInteger(20)).add(Fp.fromInteger(30)).sub(Fp.fromInteger(40)).add(Fp.fromInteger(Fp.Modulo));
    const want = Fp.fromInteger(190);
    try std.testing.expect(got.equal(want));

    const gotneg = got.neg();
    const wantneg = Fp.fromInteger(Fp.Modulo - 190);
    try std.testing.expect(gotneg.equal(wantneg));
}

test "inv" {
    const types = [_]type{Fp};

    inline for (types) |T| {
        try std.testing.expect(T.fromInteger(0).inv() == null);

        const one = T.one();
        const cases = [_]T{ T.fromInteger(2), T.fromInteger(42), T.fromInteger(T.Modulo - 1) };
        for (cases) |fe| {
            try std.testing.expect(fe.mul(fe.inv().?).equal(one));
        }
    }
}

test "sqrt" {
    // Test that a non-residue has no square root.
    const nonresidue = Fp.fromInteger(42);
    try std.testing.expect(nonresidue.legendre() != 1);
    try std.testing.expect(nonresidue.sqrt() == null);

    // Test that a residue has a square root and sqrt(b)^2=b.
    const b = Fp.fromInteger(44);
    try std.testing.expect(b.legendre() == 1);

    const b_sqrt = b.sqrt().?;
    const b_sqrt_sqr = b_sqrt.mul(b_sqrt);

    try std.testing.expect(b.equal(b_sqrt_sqr));
}

test "batch inv" {
    var fes: [25]Fp = undefined;
    for (0..fes.len) |i| {
        fes[i] = Fp.fromInteger(0x434343 + i * 0x424242);
    }

    var exp_invs: [fes.len]Fp = undefined;
    for (fes, 0..) |f, i| {
        exp_invs[i] = f.inv().?;
    }

    var got_invs: [fes.len]Fp = undefined;
    try Fp.batchInv(&got_invs, &fes);

    for (exp_invs, got_invs) |exp, got| {
        try std.testing.expect(exp.equal(got));
    }
}

test "batch inv with error" {
    var fes: [3]Fp = undefined;
    for (0..fes.len) |i| {
        fes[i] = Fp.fromInteger(0x434343 + i * 0x424242);
    }
    fes[1] = Fp.zero();

    var got_invs: [fes.len]Fp = undefined;
    const out = Fp.batchInv(&got_invs, &fes);
    try std.testing.expectError(error.CantInvertZeroElement, out);
}
