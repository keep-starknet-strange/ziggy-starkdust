const std = @import("std");
const Bandersnatch = @import("../bandersnatch.zig");
const Fp = Bandersnatch.Fp;
const Fr = Bandersnatch.Fr;
const AffinePoint = Bandersnatch.AffinePoint;

// TODO: explore if it's worth changing the API style to use receivers for outputs.

pub const ExtendedPointMSM = struct {
    x: Fp,
    y: Fp,
    t: Fp,

    pub fn identity() ExtendedPointMSM {
        return comptime fromExtendedPoint(ExtendedPoint.identity());
    }

    pub fn generator() ExtendedPointMSM {
        return comptime fromExtendedPoint(ExtendedPoint.generator());
    }

    pub fn initUnsafe(x: Fp, y: Fp) ExtendedPointMSM {
        return ExtendedPointMSM{
            .x = x,
            .y = y,
            .t = x.mul(y).mul(Bandersnatch.D),
        };
    }

    pub fn neg(p: ExtendedPointMSM) ExtendedPointMSM {
        return ExtendedPointMSM{
            .x = p.x.neg(),
            .y = p.y,
            .t = p.t.neg(),
        };
    }

    pub fn fromExtendedPoint(p: ExtendedPoint) ExtendedPointMSM {
        const z_inv = p.z.inv().?;
        const x = p.x.mul(z_inv);
        const y = p.y.mul(z_inv);
        return initUnsafe(x, y);
    }

    pub fn equal(self: ExtendedPointMSM, other: ExtendedPointMSM) bool {
        return self.x.equal(other.x) and self.y.equal(other.y) and self.t.equal(other.t);
    }
};

pub const ExtendedPoint = struct {
    x: Fp,
    y: Fp,
    t: Fp,
    z: Fp,

    pub fn init(x: Fp, y: Fp) !ExtendedPoint {
        if (!AffinePoint.isOnCurve(.{ .x = x, .y = y })) {
            return Bandersnatch.CurveError.NotInCurve;
        }
        return initUnsafe(x, y);
    }

    pub fn initUnsafe(x: Fp, y: Fp) ExtendedPoint {
        return ExtendedPoint{
            .x = x,
            .y = y,
            .t = x.mul(y),
            .z = Fp.one(),
        };
    }

    pub fn fromExtendedPointMSM(e: ExtendedPointMSM) ExtendedPoint {
        return initUnsafe(e.x, e.y);
    }

    pub fn identity() ExtendedPoint {
        const iden = comptime AffinePoint.identity();
        return comptime initUnsafe(iden.x, iden.y);
    }

    pub fn generator() ExtendedPoint {
        const gen = comptime AffinePoint.generator();
        return comptime initUnsafe(gen.x, gen.y);
    }

    pub fn neg(p: ExtendedPoint) ExtendedPoint {
        return ExtendedPoint{
            .x = p.x.neg(),
            .y = p.y,
            .t = p.t.neg(),
            .z = p.z,
        };
    }

    pub fn isZero(self: ExtendedPoint) bool {
        // Identity is {x=0, y=1, t = 0, z =1}
        // The equivalence class is therefore is {x=0, y=k, t = 0, z=k} for all k where k!=0
        const condition_1 = self.x.isZero();
        const condition_2 = self.y.equal(self.z);
        const condition_3 = !self.y.isZero();
        const condition_4 = self.t.isZero();

        return condition_1 and condition_2 and condition_3 and condition_4;
    }

    pub fn equal(p: ExtendedPoint, q: ExtendedPoint) bool {
        if (p.isZero()) {
            return q.isZero();
        }

        if (q.isZero()) {
            return false;
        }

        return (p.x.mul(q.z).equal(p.z.mul(q.x))) and (p.y.mul(q.z).equal(q.y.mul(p.z)));
    }

    pub fn add(p: ExtendedPoint, q: ExtendedPoint) ExtendedPoint {
        // https://hyperelliptic.org/EFD/g1p/auto-twisted-extended.html#addition-add-2008-hwcd
        const a = Fp.mul(p.x, q.x);
        const b = Fp.mul(p.y, q.y);
        const c = Fp.mul(Bandersnatch.D, Fp.mul(p.t, q.t));
        const d = Fp.mul(p.z, q.z);
        const e = Fp.sub(Fp.sub(Fp.mul(Fp.add(p.x, p.y), Fp.add(q.x, q.y)), a), b);
        const f = Fp.sub(d, c);
        const g = Fp.add(d, c);
        const h = Fp.sub(b, mulByA(a));

        return ExtendedPoint{
            .x = Fp.mul(e, f),
            .y = Fp.mul(g, h),
            .t = Fp.mul(e, h),
            .z = Fp.mul(f, g),
        };
    }

    pub fn mixedMsmAdd(p: ExtendedPoint, q: ExtendedPointMSM) ExtendedPoint {
        // https://hyperelliptic.org/EFD/g1p/auto-twisted-extended.html#addition-madd-2008-hwcd
        const A = Fp.mul(p.x, q.x);
        const B = Fp.mul(p.y, q.y);
        // const t0 = Fp.mul(Bandersnatch.D, q.t);
        const C = Fp.mul(p.t, q.t);
        const D = p.z;
        const t1 = Fp.add(p.x, p.y);
        const t2 = Fp.add(q.x, q.y);
        const t3 = Fp.mul(t1, t2);
        const t4 = Fp.sub(t3, A);
        const E = Fp.sub(t4, B);
        const F = Fp.sub(D, C);
        const G = Fp.add(D, C);
        const t5 = mulByA(A);
        const H = Fp.sub(B, t5);
        return ExtendedPoint{
            .x = Fp.mul(E, F),
            .y = Fp.mul(G, H),
            .t = Fp.mul(E, H),
            .z = Fp.mul(F, G),
        };
    }

    inline fn mulByA(x: Fp) Fp {
        return x.neg().mulBy5();
    }

    pub fn sub(p: ExtendedPoint, q: ExtendedPoint) ExtendedPoint {
        const neg_q = q.neg();
        return add(p, neg_q);
    }

    pub fn double(self: ExtendedPoint) ExtendedPoint {
        // https://hyperelliptic.org/EFD/g1p/auto-twisted-extended.html#doubling-dbl-2008-hwcd
        const A = self.x.square();
        const B = self.y.square();
        const t0 = self.z.square();
        const C = Fp.add(t0, t0);
        const D = mulByA(A);
        const t1 = Fp.add(self.x, self.y);
        const t2 = t1.square();
        const t3 = Fp.sub(t2, A);
        const E = Fp.sub(t3, B);
        const G = Fp.add(D, B);
        const F = Fp.sub(G, C);
        const H = Fp.sub(D, B);

        return ExtendedPoint{
            .x = Fp.mul(E, F),
            .y = Fp.mul(G, H),
            .t = Fp.mul(E, H),
            .z = Fp.mul(F, G),
        };
    }

    pub fn scalarMul(point: ExtendedPoint, scalarMont: Fr) ExtendedPoint {
        // Same as AffinePoint's equivalent method
        // using double and add : https://en.wikipedia.org/wiki/Elliptic_curve_point_multiplication#Double-and-add
        var result = identity();
        var temp = point;

        const scalar = scalarMont.toInteger();
        const one: @TypeOf(scalar) = 1;
        inline for (0..@bitSizeOf(@TypeOf(scalar))) |i| {
            if (scalar & (one << @intCast(i)) > 0) {
                result = result.add(temp);
            }
            temp = temp.double();
        }
        return result;
    }

    pub fn toAffine(self: ExtendedPoint) AffinePoint {
        if (self.isZero()) {
            return AffinePoint.identity();
        } else if (self.z.isOne()) {
            return AffinePoint.initUnsafe(self.x, self.y);
        } else {
            const z_inv = self.z.inv().?;

            const x_aff = self.x.mul(z_inv);
            const y_aff = self.y.mul(z_inv);
            return AffinePoint.initUnsafe(x_aff, y_aff);
        }
    }

    pub fn toBytes(self: ExtendedPoint) [32]u8 {
        return self.toAffine().toBytes();
    }
};
