const std = @import("std");

pub const ECError = error{
    DivisionByZero,
    XCoordinatesAreEqual,
    YCoordinateIsZero,
};

const Felt252 = @import("./starknet.zig").Felt252;

/// A type that represents a point (x,y) on an elliptic curve.
pub const ECPoint = struct {
    const Self = @This();
    x: Felt252 = Felt252.zero(),
    y: Felt252 = Felt252.zero(),

    /// Adds two points on an elliptic curve.
    /// 
    /// # Arguments
    /// - `self` - The original point.
    /// - `point` - The point that we are adding.
    /// 
    /// # Returns
    /// The sum of the elliptic curve points.
    pub fn ecAdd(self: *Self, point: ECPoint) ECError!ECPoint {

        // The x coordinates of the two points must be different.
        if (self.x.sub(point.x).equal(Felt252.zero())) {
            return ECError.XCoordinatesAreEqual;
        }
        const x_diff = self.x.sub(point.x);
        const y_diff = self.y.sub(point.y);
        const x_sum = self.x.add(point.x);
        const m = try divMod(y_diff, x_diff);
        const x = m.pow(2).sub(x_sum);
        const y = m.mul(self.x.sub(x)).sub(self.y);
        return .{ .x = x, .y = y };
    }

    /// Given a point (x, y) return (x, -y).
    /// 
    /// # Arguments
    /// - `self` - The point.
    /// 
    /// # Returns
    /// The new elliptic curve point.
    pub fn ecNeg(self: *Self) ECPoint {
        return .{ .x = self.x, .y = -self.y };
    }

    /// Doubles a point on an elliptic curve with the equation y^2 = x^3 + alpha*x + beta.
    /// 
    /// # Arguments
    /// - `self` - The point.
    /// - `alpha` - The alpha parameter of the elliptic curve.
    /// 
    /// # Returns
    /// The doubled elliptic curve point.
    pub fn ecDouble(self: *Self, alpha: Felt252) ECError!ECPoint {

        // Assumes the point is given in affine form (x, y) and has y != 0.
        if (self.y.equal(Felt252.zero())) {
            return ECError.YCoordinateIsZero;
        }
        const m = try self.ecDoubleSlope(alpha);
        const x = m.pow(2).sub(self.x.mul(Felt252.fromInteger(2)));
        const y = m.mul(self.x.sub(x)).sub(self.y);
        return .{ .x = x, .y = y };
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
            self.x.pow(2).mul(Felt252.fromInteger(3)).add(alpha), 
            self.y.mul(Felt252.fromInteger(2)),
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
    pub fn pointOnCurve(self: *Self, alpha: Felt252, beta: Felt252) bool {
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
    const x = try m.div(n);
    return x;
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
pub fn ecOpImpl(const_partial_sum: ECPoint, const_doubled_point: ECPoint, m: Felt252, alpha: Felt252, height: u32) ECError!ECPoint {
    var slope = m.toInteger();
    var partial_sum = const_partial_sum;
    var doubled_point = const_doubled_point;
    
    for (0..height) |_| {
        if (doubled_point.x.sub(partial_sum.x).equal(Felt252.zero())) {
            return ECError.XCoordinatesAreEqual;
        }
        if (slope & 1 != 0) {
            partial_sum = try partial_sum.ecAdd(doubled_point);
        }
        doubled_point = try doubled_point.ecDouble(alpha);
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
    const x = Felt252.fromInteger(3143372541908290873737380228370996772020829254218248561772745122290262847573);
    const y = Felt252.fromInteger(1721586982687138486000069852568887984211460575851774005637537867145702861131);
    const alpha = Felt252.one();
    var to_double = ECPoint{ .x = x, .y = y };
    const actual_slope = try to_double.ecDoubleSlope(alpha);
    const expected_slope = Felt252.fromInteger(3601388548860259779932034493250169083811722919049731683411013070523752439691);
    try expectEqual(expected_slope, actual_slope);
}

test "Elliptic curve math: compute double slope for valid point B" {
    const x = Felt252.fromInteger(1937407885261715145522756206040455121546447384489085099828343908348117672673);
    const y = Felt252.fromInteger(2010355627224183802477187221870580930152258042445852905639855522404179702985);
    const alpha = Felt252.one();
    var to_double = ECPoint{ .x = x, .y = y };
    const actual_slope = try to_double.ecDoubleSlope(alpha);
    const expected_slope = Felt252.fromInteger(2904750555256547440469454488220756360634457312540595732507835416669695939476);
    try expectEqual(expected_slope, actual_slope);
}

test "Elliptic curve math: EC double for valid point A" {
    const x = Felt252.fromInteger(1937407885261715145522756206040455121546447384489085099828343908348117672673);
    const y = Felt252.fromInteger(2010355627224183802477187221870580930152258042445852905639855522404179702985);
    const alpha = Felt252.one();
    var to_double = ECPoint{ .x = x, .y = y };
    const actual_ec_point = try to_double.ecDouble(alpha);
    const expected_x = Felt252.fromInteger(58460926014232092148191979591712815229424797874927791614218178721848875644);
    const expected_y = Felt252.fromInteger(1065613861227134732854284722490492186040898336012372352512913425790457998694);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "Elliptic curve math: EC double for valid point B" {
    const x = Felt252.fromInteger(3143372541908290873737380228370996772020829254218248561772745122290262847573);
    const y = Felt252.fromInteger(1721586982687138486000069852568887984211460575851774005637537867145702861131);
    const alpha = Felt252.one();
    var to_double = ECPoint{ .x = x, .y = y };
    const actual_ec_point = try to_double.ecDouble(alpha);
    const expected_x = Felt252.fromInteger(1937407885261715145522756206040455121546447384489085099828343908348117672673);
    const expected_y = Felt252.fromInteger(2010355627224183802477187221870580930152258042445852905639855522404179702985);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "Elliptic curve math: EC double for valid point C" {
    const x = Felt252.fromInteger(634630432210960355305430036410971013200846091773294855689580772209984122075);
    const y = Felt252.fromInteger(904896178444785983993402854911777165629036333948799414977736331868834995209);
    const alpha = Felt252.one();
    var to_double = ECPoint{ .x = x, .y = y };
    const actual_ec_point = try to_double.ecDouble(alpha);
    const expected_x = Felt252.fromInteger(3143372541908290873737380228370996772020829254218248561772745122290262847573);
    const expected_y = Felt252.fromInteger(1721586982687138486000069852568887984211460575851774005637537867145702861131);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "Elliptic curve math: EC add for valid pair of points A and B" {
    const x_a = Felt252.fromInteger(1183418161532233795704555250127335895546712857142554564893196731153957537489);
    const y_a = Felt252.fromInteger(1938007580204102038458825306058547644691739966277761828724036384003180924526);
    const x_b = Felt252.fromInteger(1977703130303461992863803129734853218488251484396280000763960303272760326570);
    const y_b = Felt252.fromInteger(2565191853811572867032277464238286011368568368717965689023024980325333517459);
    var point_a = ECPoint{ .x = x_a, .y = y_a };
    const point_b = ECPoint{ .x = x_b, .y = y_b };
    const actual_ec_point = try point_a.ecAdd(point_b);
    const expected_x = Felt252.fromInteger(1977874238339000383330315148209250828062304908491266318460063803060754089297);
    const expected_y = Felt252.fromInteger(2969386888251099938335087541720168257053975603483053253007176033556822156706);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "Elliptic curve math: EC add for valid pair of points C and D" {
    const x_c = Felt252.fromInteger(3139037544796708144595053687182055617920475701120786241351436619796497072089);
    const y_c = Felt252.fromInteger(2119589567875935397690285099786081818522144748339117565577200220779667999801);
    const x_d = Felt252.fromInteger(3324833730090626974525872402899302150520188025637965566623476530814354734325);
    const y_d = Felt252.fromInteger(3147007486456030910661996439995670279305852583596209647900952752170983517249);
    var point_c = ECPoint{ .x = x_c, .y = y_c };
    const point_d = ECPoint{ .x = x_d, .y = y_d };
    const actual_ec_point = try point_c.ecAdd(point_d);
    const expected_x = Felt252.fromInteger(1183418161532233795704555250127335895546712857142554564893196731153957537489);
    const expected_y = Felt252.fromInteger(1938007580204102038458825306058547644691739966277761828724036384003180924526);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "Elliptic curve math: point_is_on_curve_a" {
    const x = Felt252.fromInteger(874739451078007766457464989774322083649278607533249481151382481072868806602);
    const y = Felt252.fromInteger(152666792071518830868575557812948353041420400780739481342941381225525861407);
    const alpha = Felt252.one();
    const beta = Felt252.fromInteger(3141592653589793238462643383279502884197169399375105820974944592307816406665);
    var point = ECPoint{ .x = x, .y = y };
    try expect(point.pointOnCurve(alpha, beta));
}

test "Elliptic curve math: point_is_on_curve_b" {
    const x = Felt252.fromInteger(3139037544796708144595053687182055617920475701120786241351436619796497072089);
    const y = Felt252.fromInteger(2119589567875935397690285099786081818522144748339117565577200220779667999801);
    const alpha = Felt252.one();
    const beta = Felt252.fromInteger(3141592653589793238462643383279502884197169399375105820974944592307816406665);
    var point = ECPoint{ .x = x, .y = y };
    try expect(point.pointOnCurve(alpha, beta));
}

test "Elliptic curve math: point_is_not_on_curve_a" {
    const x = Felt252.fromInteger(874739454078007766457464989774322083649278607533249481151382481072868806602);
    const y = Felt252.fromInteger(152666792071518830868575557812948353041420400780739481342941381225525861407);
    const alpha = Felt252.one();
    const beta = Felt252.fromInteger(3141592653589793238462643383279502884197169399375105820974944592307816406665);
    var point = ECPoint{ .x = x, .y = y };
    try expect(!point.pointOnCurve(alpha, beta));
}

test "Elliptic curve math: point_is_not_on_curve_b" {
    const x = Felt252.fromInteger(3139037544756708144595053687182055617927475701120786241351436619796497072089);
    const y = Felt252.fromInteger(2119589567875935397690885099786081818522144748339117565577200220779667999801);
    const alpha = Felt252.one();
    const beta = Felt252.fromInteger(3141592653589793238462643383279502884197169399375105820974944592307816406665);
    var point = ECPoint{ .x = x, .y = y };
    try expect(!point.pointOnCurve(alpha, beta));
}

test "Elliptic curve math: compute_ec_op_impl_valid_a" {
    const partial_sum = ECPoint{
        .x = Felt252.fromInteger(3139037544796708144595053687182055617920475701120786241351436619796497072089),
        .y = Felt252.fromInteger(2119589567875935397690285099786081818522144748339117565577200220779667999801),
    };
    const doubled_point = ECPoint{
        .x = Felt252.fromInteger(874739451078007766457464989774322083649278607533249481151382481072868806602),
        .y = Felt252.fromInteger(152666792071518830868575557812948353041420400780739481342941381225525861407),
    };
    const m = Felt252.fromInteger(34);
    const alpha = Felt252.one();
    const height = 256;
    const actual_ec_point = try ecOpImpl(partial_sum, doubled_point, m, alpha, height);
    const expected_ec_point = ECPoint{
        .x = Felt252.fromInteger(1977874238339000383330315148209250828062304908491266318460063803060754089297),
        .y = Felt252.fromInteger(2969386888251099938335087541720168257053975603483053253007176033556822156706),
    };

    try expectEqual(actual_ec_point, expected_ec_point);
}

test "Elliptic curve math: compute_ec_op_impl_valid_b" {
    const partial_sum = ECPoint{
        .x = Felt252.fromInteger(2962412995502985605007699495352191122971573493113767820301112397466445942584),
        .y = Felt252.fromInteger(214950771763870898744428659242275426967582168179217139798831865603966154129),
    };
    const doubled_point = ECPoint{
        .x = Felt252.fromInteger(874739451078007766457464989774322083649278607533249481151382481072868806602),
        .y = Felt252.fromInteger(152666792071518830868575557812948353041420400780739481342941381225525861407),
    };
    const m = Felt252.fromInteger(34);
    const alpha = Felt252.one();
    const height = 256;
    const actual_ec_point = try ecOpImpl(partial_sum, doubled_point, m, alpha, height);
    const expected_ec_point = ECPoint{
        .x = Felt252.fromInteger(2778063437308421278851140253538604815869848682781135193774472480292420096757),
        .y = Felt252.fromInteger(3598390311618116577316045819420613574162151407434885460365915347732568210029),
    };

    try expectEqual(actual_ec_point, expected_ec_point);
}

test "Elliptic curve math: compute_ec_op_invalid_same_x_coordinate" {
    const partial_sum = ECPoint{
        .x = Felt252.one(),
        .y = Felt252.fromInteger(9),
    };
    const doubled_point = ECPoint{
        .x = Felt252.one(),
        .y = Felt252.fromInteger(12),
    };
    const m = Felt252.fromInteger(34);
    const alpha = Felt252.one();
    const height = 256;
    const actual_ec_point = ecOpImpl(partial_sum, doubled_point, m, alpha, height);

    try expectError(ECError.XCoordinatesAreEqual, actual_ec_point);
}