const std = @import("std");

pub const ECError = error{
    DivisionByZero,
    XCoordinatesAreEqual,
    YCoordinateIsZero,
};

const Felt252 = @import("./starknet.zig").Felt252;

// A type that represents a point (x,y) on an elliptic curve.
pub const ECPoint = struct {
    const Self = @This();
    x: Felt252 = Felt252.zero(),
    y: Felt252 = Felt252.zero(),
};

// Divides one field element by another.
// Finds a nonnegative integer 0 <= x < p such that (m * x) % p == n.
// # Arguments
// - `m` - The first felt.
// - `n` - The second felt.
// # Returns
// The result of the field modulo division.
pub fn divMod(m: Felt252, n: Felt252) ECError!Felt252 {
    const x = try m.div(n);
    return x;
}

// Adds two points on an elliptic curve.
// # Arguments
// - `point1` - The first point.
// - `point2` - The second point.
// # Returns
// The sum of the elliptic curve points.
pub fn ecAdd(point1: ECPoint, point2: ECPoint) ECError!ECPoint {

    // The x coordinates of the two points must be different.
    if (point1.x.sub(point2.x).equal(Felt252.zero())) {
        return ECError.XCoordinatesAreEqual;
    }
    const x_diff = point1.x.sub(point2.x);
    const y_diff = point1.y.sub(point2.y);
    const x_sum = point1.x.add(point2.x);
    const m = try divMod(y_diff, x_diff);
    const x = m.pow(2).sub(x_sum);
    const y = m.mul(point1.x.sub(x)).sub(point1.y);
    return ECPoint{ .x = x, .y = y };
}

// Given a point (x, y) return (x, -y)..
// # Arguments
// - `point` - The point.
// # Returns
// The new elliptic curve point.
pub fn ecNeg(point: ECPoint) ECPoint {
    return ECPoint{ .x = point.x, .y = -point.y };
}

// Doubles a point on an elliptic curve with the equation y^2 = x^3 + alpha*x + beta.
// # Arguments
// - `point` - The point.
// - `alpha` - The alpha parameter of the elliptic curve.
// # Returns
// The doubled elliptic curve point.
pub fn ecDouble(point: ECPoint, alpha: Felt252) ECError!ECPoint {

    // Assumes the point is given in affine form (x, y) and has y != 0.
    if (point.y.equal(Felt252.zero())) {
        return ECError.YCoordinateIsZero;
    }
    const m = try ecDoubleSlope(point, alpha);
    const x = m.pow(2).sub(point.x.mul(Felt252.fromInteger(2)));
    const y = m.mul(point.x.sub(x)).sub(point.y);
    return ECPoint{ .x = x, .y = y };
}

// Computes the slope of an elliptic curve with the equation y^2 = x^3 + alpha*x + beta, at
// the given point.
// # Arguments
// - `point` - The point.
// - `alpha` - The alpha parameter of the elliptic curve.
// # Returns
// The slope.
pub fn ecDoubleSlope(point: ECPoint, alpha: Felt252) ECError!Felt252 {
    const m = try divMod(point.x.pow(2).mul(Felt252.fromInteger(3)).add(alpha), point.y.mul(Felt252.fromInteger(2)));
    return m;
}

pub fn ecMul() void {
    // TODO: Implement.
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "compute double slope for valid point A" {
    const x = Felt252.fromInteger(3143372541908290873737380228370996772020829254218248561772745122290262847573);
    const y = Felt252.fromInteger(1721586982687138486000069852568887984211460575851774005637537867145702861131);
    const alpha = Felt252.one();
    const to_double = ECPoint{ .x = x, .y = y };
    const actual_slope = try ecDoubleSlope(to_double, alpha);
    const expected_slope = Felt252.fromInteger(3601388548860259779932034493250169083811722919049731683411013070523752439691);
    try expectEqual(expected_slope, actual_slope);
}

test "compute double slope for valid point B" {
    const x = Felt252.fromInteger(1937407885261715145522756206040455121546447384489085099828343908348117672673);
    const y = Felt252.fromInteger(2010355627224183802477187221870580930152258042445852905639855522404179702985);
    const alpha = Felt252.one();
    const to_double = ECPoint{ .x = x, .y = y };
    const actual_slope = try ecDoubleSlope(to_double, alpha);
    const expected_slope = Felt252.fromInteger(2904750555256547440469454488220756360634457312540595732507835416669695939476);
    try expectEqual(expected_slope, actual_slope);
}

test "EC double for valid point A" {
    const x = Felt252.fromInteger(1937407885261715145522756206040455121546447384489085099828343908348117672673);
    const y = Felt252.fromInteger(2010355627224183802477187221870580930152258042445852905639855522404179702985);
    const alpha = Felt252.one();
    const to_double = ECPoint{ .x = x, .y = y };
    const actual_ec_point = try ecDouble(to_double, alpha);
    const expected_x = Felt252.fromInteger(58460926014232092148191979591712815229424797874927791614218178721848875644);
    const expected_y = Felt252.fromInteger(1065613861227134732854284722490492186040898336012372352512913425790457998694);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "EC double for valid point B" {
    const x = Felt252.fromInteger(3143372541908290873737380228370996772020829254218248561772745122290262847573);
    const y = Felt252.fromInteger(1721586982687138486000069852568887984211460575851774005637537867145702861131);
    const alpha = Felt252.one();
    const to_double = ECPoint{ .x = x, .y = y };
    const actual_ec_point = try ecDouble(to_double, alpha);
    const expected_x = Felt252.fromInteger(1937407885261715145522756206040455121546447384489085099828343908348117672673);
    const expected_y = Felt252.fromInteger(2010355627224183802477187221870580930152258042445852905639855522404179702985);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "EC double for valid point C" {
    const x = Felt252.fromInteger(634630432210960355305430036410971013200846091773294855689580772209984122075);
    const y = Felt252.fromInteger(904896178444785983993402854911777165629036333948799414977736331868834995209);
    const alpha = Felt252.one();
    const to_double = ECPoint{ .x = x, .y = y };
    const actual_ec_point = try ecDouble(to_double, alpha);
    const expected_x = Felt252.fromInteger(3143372541908290873737380228370996772020829254218248561772745122290262847573);
    const expected_y = Felt252.fromInteger(1721586982687138486000069852568887984211460575851774005637537867145702861131);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "EC add for valid pair of points A and B" {
    const x_a = Felt252.fromInteger(1183418161532233795704555250127335895546712857142554564893196731153957537489);
    const y_a = Felt252.fromInteger(1938007580204102038458825306058547644691739966277761828724036384003180924526);
    const x_b = Felt252.fromInteger(1977703130303461992863803129734853218488251484396280000763960303272760326570);
    const y_b = Felt252.fromInteger(2565191853811572867032277464238286011368568368717965689023024980325333517459);
    const point_a = ECPoint{ .x = x_a, .y = y_a };
    const point_b = ECPoint{ .x = x_b, .y = y_b };
    const actual_ec_point = try ecAdd(point_a, point_b);
    const expected_x = Felt252.fromInteger(1977874238339000383330315148209250828062304908491266318460063803060754089297);
    const expected_y = Felt252.fromInteger(2969386888251099938335087541720168257053975603483053253007176033556822156706);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}

test "EC add for valid pair of points C and D" {
    const x_c = Felt252.fromInteger(3139037544796708144595053687182055617920475701120786241351436619796497072089);
    const y_c = Felt252.fromInteger(2119589567875935397690285099786081818522144748339117565577200220779667999801);
    const x_d = Felt252.fromInteger(3324833730090626974525872402899302150520188025637965566623476530814354734325);
    const y_d = Felt252.fromInteger(3147007486456030910661996439995670279305852583596209647900952752170983517249);
    const point_c = ECPoint{ .x = x_c, .y = y_c };
    const point_d = ECPoint{ .x = x_d, .y = y_d };
    const actual_ec_point = try ecAdd(point_c, point_d);
    const expected_x = Felt252.fromInteger(1183418161532233795704555250127335895546712857142554564893196731153957537489);
    const expected_y = Felt252.fromInteger(1938007580204102038458825306058547644691739966277761828724036384003180924526);
    const expected_ec_point = ECPoint{ .x = expected_x, .y = expected_y };
    try expectEqual(expected_ec_point, actual_ec_point);
}
