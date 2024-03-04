// code ported from starknet-curve:
// https://github.com/xJonathanLEI/starknet-rs/blob/0857bd6cd3bd34cbb06708f0a185757044171d8d/starknet-curve/src/ec_point.rs
const std = @import("std");
const Felt252 = @import("../../fields/starknet.zig").Felt252;
pub const ALPHA = @import("./curve_params.zig").ALPHA;
pub const BETA = @import("./curve_params.zig").BETA;

/// Enum representing possible errors for elliptic curve operations.
pub const ECError = error{
    /// Error indicating division by zero.
    DivisionByZero,
    /// Error indicating that x-coordinates are equal.
    XCoordinatesAreEqual,
    /// Error indicating that the y-coordinate is zero.
    YCoordinateIsZero,
};

pub const ProjectivePoint = struct {
    const Self = @This();

    x: Felt252 = Felt252.zero(),
    y: Felt252 = Felt252.zero(),
    z: Felt252 = Felt252.one(),
    infinity: bool = false,

    pub fn fromAffinePoint(p: AffinePoint) Self {
        return .{
            .x = p.x,
            .y = p.y,
        };
    }

    fn identity() Self {
        return .{
            .infinity = true,
        };
    }

    pub fn doubleAssign(self: *Self) void {
        if (self.infinity)
            return;

        // t=3x^2+az^2 with a=1 from stark curve
        const t = Felt252.three().mul(self.x).mul(self.x).add(self.z.mul(self.z));
        const u = Felt252.two().mul(self.y).mul(self.z);
        const v = Felt252.two().mul(u).mul(self.x).mul(self.y);
        const w = t.mul(t).sub(Felt252.two().mul(v));

        const uy = u.mul(self.y);

        self.* = .{
            .x = u.mul(w),
            .y = t.mul(v.sub(w)).sub(Felt252.two().mul(uy).mul(uy)),
            .z = u.mul(u).mul(u),
            .infinity = self.infinity,
        };
    }

    pub fn mulByBits(self: Self, rhs: [@bitSizeOf(u256)]bool) Self {
        var product = ProjectivePoint.identity();

        inline for (1..@bitSizeOf(u256) + 1) |idx| {
            product.doubleAssign();
            if (rhs[@bitSizeOf(u256) - idx]) {
                product.addAssign(self);
            }
        }
        return product;
    }

    fn addAssign(self: *Self, rhs: ProjectivePoint) void {
        if (rhs.infinity)
            return;

        if (self.infinity) {
            self.* = rhs;
            return;
        }

        const u_0 = self.x.mul(rhs.z);
        const u_1 = rhs.x.mul(self.z);
        if (u_0.equal(u_1)) {
            self.doubleAssign();
            return;
        }

        const t0 = self.y.mul(rhs.z);
        const t1 = rhs.y.mul(self.z);
        const t = t0.sub(t1);

        const u = u_0.sub(u_1);
        const u_2 = u.mul(u);

        const v = self.z.mul(rhs.z);

        // t * t * v - u2 * (u0 + u1);
        const w = t.mul(t.mul(v)).sub(u_2.mul(u_0.add(u_1)));
        const u_3 = u.mul(u_2);

        self.* = .{
            .x = u.mul(w),
            .y = t.mul(u_0.mul(u_2).sub(w)).sub(t0.mul(u_3)),
            .z = u_3.mul(v),
            .infinity = self.infinity,
        };
    }

    pub fn addAssignAffinePoint(self: *Self, rhs: AffinePoint) void {
        if (rhs.infinity)
            return;

        if (self.infinity) {
            self.* = .{
                .x = rhs.x,
                .y = rhs.y,
                .z = Felt252.one(),
                .infinity = rhs.infinity,
            };
            return;
        }

        const u_0 = self.x;
        const u_1 = rhs.x.mul(self.z);
        const t0 = self.y;
        const t1 = rhs.y.mul(self.z);

        if (u_0.equal(u_1)) {
            if (!t0.equal(t1)) {
                self.infinity = true;
            } else {
                self.doubleAssign();
            }
            return;
        }

        const t = t0.sub(t1);
        const u = u_0.sub(u_1);
        const u_2 = u.mul(u);

        const v = self.z;
        const w = t.mul(t).mul(v).sub(u_2.mul(u_0.add(u_1)));
        const u_3 = u.mul(u_2);

        const x = u.mul(w);
        const y = t.mul(u_0.mul(u_2).sub(w)).sub(t0.mul(u_3));
        const z = u_3.mul(v);

        self.* = .{
            .x = x,
            .y = y,
            .z = z,
            .infinity = self.infinity,
        };
    }
};

pub const AffinePoint = struct {
    const Self = @This();
    x: Felt252,
    y: Felt252,
    alpha: Felt252,
    infinity: bool,

    /// Initializes an `AffinePoint` with the specified x and y coordinates.
    ///
    /// # Parameters
    /// - `x`: The x-coordinate of the point.
    /// - `y`: The y-coordinate of the point.
    ///
    /// # Returns
    /// An initialized `ECPoint` with the provided coordinates.
    pub fn initUnchecked(x: Felt252, y: Felt252, alpha: Felt252, infinity: bool) Self {
        return .{ .x = x, .y = y, .alpha = alpha, .infinity = infinity };
    }

    pub fn add(self: Self, other: Self) Self {
        var cp = self;
        var cp_other = other;

        Self.addAssign(&cp, &cp_other);
        return cp;
    }

    pub fn sub(self: Self, other: Self) Self {
        var cp = self;
        cp.subAssign(other);
        return cp;
    }

    pub fn subAssign(self: *Self, rhs: Self) void {
        var rhs_copy = rhs;

        rhs_copy.y = rhs_copy.y.neg();
        self.addAssign(&rhs_copy);
    }

    pub fn addAssign(self: *Self, rhs: *AffinePoint) void {
        if (rhs.infinity)
            return;

        if (self.infinity) {
            self.* = .{ .x = rhs.x, .y = rhs.y, .alpha = rhs.alpha, .infinity = rhs.infinity };
            return;
        }

        if (self.x.equal(rhs.x)) {
            if (self.y.equal(rhs.y.neg())) {
                self.* = .{
                    .x = Felt252.zero(),
                    .y = Felt252.zero(),
                    .alpha = ALPHA,
                    .infinity = true,
                };
                return;
            }
            self.doubleAssign();
            return;
        }

        // l = (y2-y1)/(x2-x1)
        const lambda = rhs.y.sub(self.y).mul(rhs.x.sub(self.x).inv().?);

        const result_x = lambda.mul(lambda).sub(self.x).sub(rhs.x);
        self.y = lambda.mul(self.x.sub(result_x)).sub(self.y);
        self.x = result_x;
    }

    pub fn doubleAssign(self: *Self) void {
        if (self.infinity)
            return;

        // l = (3x^2+a)/2y with a=1 from stark curve
        const lambda = Felt252.three().mul(self.x.mul(self.x)).add(Felt252.one()).mul(Felt252.two().mul(self.y).inv().?);

        const result_x = lambda.mul(lambda).sub(self.x).sub(self.x);
        self.y = lambda.mul(self.x.sub(result_x)).sub(self.y);
        self.x = result_x;
    }

    pub fn fromX(x: Felt252) error{SqrtNotExist}!Self {
        const y_squared = x.mul(x).mul(x).add(ALPHA.mul(x)).add(BETA);

        return .{
            .x = x,
            .y = if (y_squared.sqrt()) |y| y else return error.SqrtNotExist,
            .alpha = ALPHA,
            .infinity = false,
        };
    }

    pub fn fromProjectivePoint(p: ProjectivePoint) Self {
        // always one, that is why we can unwrap, unreachable will not happen
        const zinv = if (p.z.inv()) |zinv| zinv else unreachable;

        return .{
            .x = p.x.mul(zinv),
            .y = p.y.mul(zinv),
            .alpha = ALPHA,
            .infinity = false,
        };
    }

    /// Doubles a point on an elliptic curve with the equation y^2 = x^3 + alpha*x + beta.
    ///
    /// # Arguments
    /// - `self` - The point.
    /// - `alpha` - The alpha parameter of the elliptic curve.
    ///
    /// # Returns
    /// The doubled elliptic curve point.
    pub fn ecDouble(self: *Self) ECError!AffinePoint {

        // Assumes the point is given in affine form (x, y) and has y != 0.
        if (self.y.equal(Felt252.zero())) {
            return ECError.YCoordinateIsZero;
        }
        const m = try self.ecDoubleSlope(self.alpha);
        const x = m.pow(2).sub(self.x.mul(Felt252.two()));
        const y = m.mul(self.x.sub(x)).sub(self.y);
        return .{ .x = x, .y = y, .alpha = self.alpha, .infinity = self.infinity };
    }

    /// Computes the slope of an elliptic curve with the equation y^2 = x^3 + alpha*x + beta, at
    /// the given point.
    ///
    /// # Arguments
    /// - `self` - The point.
    /// - `alpha` - The alpha parameter of the elliptic curve.
    ///
    /// # Returns
    /// The slope.
    pub fn ecDoubleSlope(self: *Self, alpha: Felt252) ECError!Felt252 {
        return try divMod(
            self.x.pow(2).mul(Felt252.three()).add(alpha),
            self.y.mul(Felt252.two()),
        );
    }

    /// Returns True if the point (x, y) is on the elliptic curve defined as
    /// y^2 = x^3 + alpha * x + beta, or False otherwise.
    ///
    /// # Arguments
    /// - `self` - The point.
    /// - `alpha` - The alpha parameter of the elliptic curve.
    /// - `beta` - The beta parameter of the elliptic curve.
    ///
    /// # Returns boolean.
    pub fn pointOnCurve(self: *const Self, alpha: Felt252, beta: Felt252) bool {
        const lhs = self.y.pow(2);
        const rhs = self.x.pow(3).add(self.x.mul(alpha).add(beta));
        return lhs.equal(rhs);
    }
};

/// Divides one field element by another.
/// Finds a nonnegative integer 0 <= x < p such that (m * x) % p == n.
///
/// # Arguments
/// - `m` - The first felt.
/// - `n` - The second felt.
///
/// # Returns
/// The result of the field modulo division.
pub fn divMod(m: Felt252, n: Felt252) ECError!Felt252 {
    return try m.div(n);
}

/// Calculates the result of the elliptic curve operation P + m * Q,
/// where P = const_partial_sum, and Q = const_doubled_point
/// are points on the elliptic curve defined as:
/// y^2 = x^3 + alpha * x + beta.
///
/// # Arguments
/// - `const_partial_sum` - The point P.
/// - `const_doubled_point` - The point Q.
///
/// # Returns
/// The result of the EC operation P + m * Q.
pub fn ecOpImpl(const_partial_sum: AffinePoint, const_doubled_point: AffinePoint, m: Felt252, height: u32) ECError!AffinePoint {
    var slope = m.toInteger();
    var partial_sum = const_partial_sum;
    var doubled_point = const_doubled_point;

    for (0..height) |_| {
        if (doubled_point.x.sub(partial_sum.x).equal(Felt252.zero())) {
            return ECError.XCoordinatesAreEqual;
        }
        if (slope & 1 != 0) {
            partial_sum = partial_sum.add(doubled_point);
        }
        doubled_point = try doubled_point.ecDouble();
        slope = slope >> 1;
    }

    return partial_sum;
}

/// ************************************************************
/// *                         TESTS                            *
/// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Elliptic curve math: compute double slope for valid point A" {
    const x = Felt252.fromInt(u256, 3143372541908290873737380228370996772020829254218248561772745122290262847573);
    const y = Felt252.fromInt(u256, 1721586982687138486000069852568887984211460575851774005637537867145702861131);
    const alpha = Felt252.one();
    var to_double = AffinePoint{ .x = x, .y = y, .alpha = Felt252.one(), .infinity = false };
    const actual_slope = try to_double.ecDoubleSlope(alpha);
    const expected_slope = Felt252.fromInt(u256, 3601388548860259779932034493250169083811722919049731683411013070523752439691);
    try expectEqual(expected_slope, actual_slope);
}

test "Elliptic curve math: compute double slope for valid point B" {
    const x = Felt252.fromInt(u256, 1937407885261715145522756206040455121546447384489085099828343908348117672673);
    const y = Felt252.fromInt(u256, 2010355627224183802477187221870580930152258042445852905639855522404179702985);
    const alpha = Felt252.one();
    var to_double = AffinePoint{ .x = x, .y = y, .alpha = Felt252.one(), .infinity = false };
    const actual_slope = try to_double.ecDoubleSlope(alpha);
    const expected_slope = Felt252.fromInt(u256, 2904750555256547440469454488220756360634457312540595732507835416669695939476);
    try expectEqual(expected_slope, actual_slope);
}

test "Elliptic curve math: compute_ec_op_impl_valid_a" {
    const partial_sum = AffinePoint{ .x = Felt252.fromInt(u256, 3139037544796708144595053687182055617920475701120786241351436619796497072089), .y = Felt252.fromInt(u256, 2119589567875935397690285099786081818522144748339117565577200220779667999801), .alpha = Felt252.one(), .infinity = false };
    const doubled_point = AffinePoint{ .x = Felt252.fromInt(u256, 874739451078007766457464989774322083649278607533249481151382481072868806602), .y = Felt252.fromInt(u256, 152666792071518830868575557812948353041420400780739481342941381225525861407), .alpha = Felt252.one(), .infinity = false };
    const m = Felt252.fromInt(u8, 34);
    const height = 256;
    const actual_ec_point = try ecOpImpl(partial_sum, doubled_point, m, height);
    const expected_ec_point = AffinePoint{ .x = Felt252.fromInt(u256, 1977874238339000383330315148209250828062304908491266318460063803060754089297), .y = Felt252.fromInt(u256, 2969386888251099938335087541720168257053975603483053253007176033556822156706), .alpha = Felt252.one(), .infinity = false };

    try expectEqual(actual_ec_point, expected_ec_point);
}

test "Elliptic curve math: compute_ec_op_impl_valid_b" {
    const partial_sum = AffinePoint{ .x = Felt252.fromInt(u256, 2962412995502985605007699495352191122971573493113767820301112397466445942584), .y = Felt252.fromInt(u256, 214950771763870898744428659242275426967582168179217139798831865603966154129), .alpha = Felt252.one(), .infinity = false };
    const doubled_point = AffinePoint{ .x = Felt252.fromInt(u256, 874739451078007766457464989774322083649278607533249481151382481072868806602), .y = Felt252.fromInt(u256, 152666792071518830868575557812948353041420400780739481342941381225525861407), .alpha = Felt252.one(), .infinity = false };
    const m = Felt252.fromInt(u8, 34);
    const height = 256;
    const actual_ec_point = try ecOpImpl(partial_sum, doubled_point, m, height);
    const expected_ec_point = AffinePoint{ .x = Felt252.fromInt(u256, 2778063437308421278851140253538604815869848682781135193774472480292420096757), .y = Felt252.fromInt(u256, 3598390311618116577316045819420613574162151407434885460365915347732568210029), .alpha = Felt252.one(), .infinity = false };

    try expectEqual(actual_ec_point, expected_ec_point);
}

test "Elliptic curve math: compute_ec_op_invalid_same_x_coordinate" {
    const partial_sum = AffinePoint{ .x = Felt252.one(), .y = Felt252.fromInt(u8, 9), .alpha = Felt252.one(), .infinity = false };
    const doubled_point = AffinePoint{ .x = Felt252.one(), .y = Felt252.fromInt(u8, 12), .alpha = Felt252.one(), .infinity = false };
    const m = Felt252.fromInt(u8, 34);
    const height = 256;
    const actual_ec_point = ecOpImpl(partial_sum, doubled_point, m, height);

    try expectError(ECError.XCoordinatesAreEqual, actual_ec_point);
}
