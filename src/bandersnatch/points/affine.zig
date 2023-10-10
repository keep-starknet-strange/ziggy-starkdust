const Bandersnatch = @import("../bandersnatch.zig");
const Fp = Bandersnatch.Fp;
const Fr = Bandersnatch.Fr;

const AffinePoint = @This();

x: Fp,
y: Fp,

// init creates a new point with the given x and y co-ordinates, and checks that is on the curve.
pub fn init(x: Fp, y: Fp) !AffinePoint {
    const p = initUnsafe(x, y);
    if (!p.isOnCurve()) return error.NotInCurve;

    return p;
}

// initUnsafe is used to create a point without checking if it is on the curve.
pub fn initUnsafe(x: Fp, y: Fp) AffinePoint {
    return AffinePoint{ .x = x, .y = y };
}

pub fn generator() AffinePoint {
    // Generator point was taken from the bandersnatch paper: https://ia.cr/2021/1152
    const gen = comptime blk: {
        const xTe = Fp.fromInteger(0x29c132cc2c0b34c5743711777bbe42f32b79c022ad998465e1e71866a252ae18);
        const yTe = Fp.fromInteger(0x2a6c669eda123e0f157d8b50badcd586358cad81eee464605e3167b6cc974166);
        break :blk init(xTe, yTe) catch unreachable;
    };
    return gen;
}

pub fn neg(self: AffinePoint) AffinePoint {
    return AffinePoint{ .x = self.x.neg(), .y = self.y };
}

pub fn add(p: AffinePoint, q: AffinePoint) AffinePoint {
    const x1 = p.x;
    const y1 = p.y;
    const x2 = q.x;
    const y2 = q.y;

    const one = Fp.one();

    const x1y2 = x1 * y2;

    const y1x2 = y1 * x2;
    const ax1x2 = x1 * x2 * Bandersnatch.A;
    const y1y2 = y1 * y2;

    const dx1x2y1y2 = x1y2 * y1x2 * Bandersnatch.D;

    const x_num = x1y2 + y1x2;

    const x_den = one + dx1x2y1y2;

    const y_num = y1y2 - ax1x2;

    const y_den = one - dx1x2y1y2;

    const x = x_num / x_den;

    const y = y_num / y_den;

    return AffinePoint{ .x = x, .y = y };
}

pub fn sub(p: AffinePoint, q: AffinePoint) AffinePoint {
    return p.add(q.neg());
}

pub fn double(p: AffinePoint) AffinePoint {
    return p.add(p);
}

pub fn eq(self: AffinePoint, q: AffinePoint) bool {
    return self.x.equal(q.x) and self.y.equal(q.y);
}

pub fn identity() AffinePoint {
    return comptime AffinePoint{ .x = Fp.zero(), .y = Fp.one() };
}

pub fn scalarMul(point: AffinePoint, scalar: Fr) AffinePoint {
    // using double and add : https://en.wikipedia.org/wiki/Elliptic_curve_point_multiplication#Double-and-add
    const result = identity();
    const temp = point;

    for (scalar.fe) |limb| {
        for (0..@bitSizeOf(scalar.fe[0])) |i| {
            if (scalar.fe[limb] & 1 << (limb * i) == 1) {
                result.add(result, temp);
            }
            temp.double(temp);
        }
    }
    return result;
}

pub fn toBytes(self: AffinePoint) [32]u8 {
    const mCompressedNegative = 0x80;
    const mCompressedPositive = 0x00;

    var mask: u8 = mCompressedPositive;
    if (self.y.lexographicallyLargest()) {
        mask = mCompressedNegative;
    }

    var xBytes = self.x.toBytes();
    xBytes[31] |= mask;

    return xBytes;
}

pub fn isOnCurve(self: AffinePoint) bool {
    const x_sq = self.x.mul(self.x);
    const y_sq = self.y.mul(self.y);

    const dxy_sq = x_sq.mul(y_sq).mul(Bandersnatch.D);
    const a_x_sq = Bandersnatch.A.mul(x_sq);

    const one = Fp.one();

    const rhs = one.add(dxy_sq);
    const lhs = a_x_sq.add(y_sq);

    return lhs.equal(rhs);
}

pub fn getYCoordinate(x: Fp, returnPositiveY: bool) !Fp {
    const one = Fp.one();

    const num = x.mul(x);
    const den = num.mul(Bandersnatch.D).sub(one);

    const num2 = num.mul(Bandersnatch.A).sub(one);

    // This can only be None if the denominator is zero
    var y = try num2.div(den); // y^2

    // This means that the square root does not exist
    y = y.sqrt() orelse return error.NotInCurve;

    const is_largest = y.lexographicallyLargest();
    if (returnPositiveY == is_largest) {
        return y;
    }
    return y.neg();
}
