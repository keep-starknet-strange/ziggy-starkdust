const std = @import("std");
const starknet = @import("starknet");
const MathError = @import("../../vm/error.zig").MathError;
const Int = std.math.big.int.Managed;

/// Maximum value of [Felt]. Equals to 2^251 + 17 * 2^192.
pub inline fn felt252MaxValue() starknet.fields.Felt252 {
    comptime {
        return starknet.fields.Felt252.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020480);
    }
}

///Returns the integer square root of the nonnegative integer n.
///This is the floor of the exact square root of n.
///Unlike math.sqrt(), this function doesn't have rounding error issues.
pub fn isqrt(comptime T: type, n: T) !T {
    var x = n;
    var y = (n + 1) >> @as(u32, 1);

    while (y < x) {
        x = y;
        y = (@divFloor(n, x) + x) >> @as(u32, 1);
    }

    if (!(std.math.pow(T, x, 2) <= n and n < std.math.pow(T, x + 1, 2))) {
        return error.FailedToGetSqrt;
    }

    return x;
}

pub fn multiplyModulus(a: u512, b: u512, modulus: u512) u512 {
    return (a * b) % modulus;
}

pub fn multiplyModulusBigInt(allocator: std.mem.Allocator, a: Int, b: Int, modulus: Int) !Int {
    var result = try Int.init(allocator);
    errdefer result.deinit();

    try multiplyModulusBigIntWithPtr(allocator, a, b, modulus, &result);

    return result;
}

pub fn multiplyModulusBigIntWithPtr(allocator: std.mem.Allocator, a: Int, b: Int, modulus: Int, result: *Int) !void {
    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.mul(&a, &b);

    try tmp.divFloor(result, &tmp, &modulus);
}

pub fn powModulusBigInt(allocator: std.mem.Allocator, b: Int, e: Int, modulus: Int) !Int {
    var result = try Int.initSet(allocator, 0);
    errdefer result.deinit();

    try powModulusBigIntWithPtr(allocator, b, e, modulus, &result);
    return result;
}

pub fn powModulusBigIntWithPtr(allocator: std.mem.Allocator, b: Int, e: Int, modulus: Int, result: *Int) !void {
    var base = try b.clone();
    defer base.deinit();

    var exponent = try e.clone();
    defer exponent.deinit();

    var tmp = try Int.initSet(allocator, 1);
    defer tmp.deinit();

    var tmp2 = try Int.initSet(allocator, 1);
    defer tmp2.deinit();

    if (modulus.eql(tmp))
        return;

    try tmp.divFloor(&base, &base, &modulus);

    try result.set(1);

    while (!exponent.eqlZero()) {
        try tmp.set(1);
        try tmp.bitAnd(&exponent, &tmp);

        if (tmp.eql(tmp2)) {
            try multiplyModulusBigIntWithPtr(allocator, result.*, base, modulus, result);
        }

        try multiplyModulusBigIntWithPtr(allocator, base, base, modulus, &base);

        try exponent.shiftRight(&exponent, 1);
    }
}

pub fn powModulus(b: u512, e: u512, modulus: u512) u512 {
    var base: u512 = b;
    var exponent: u512 = e;

    if (modulus == 1) {
        return 0;
    }

    base = base % modulus;

    var result: u512 = 1;

    while (exponent > 0) {
        if ((exponent & 1) == 1) {
            result = multiplyModulus(result, base, modulus);
        }

        base = multiplyModulus(base, base, modulus);
        exponent = exponent >> 1;
    }

    return result;
}

pub fn legendre(a: u512, p: u512) u512 {
    return powModulus(a, (p - 1) / 2, p);
}

pub fn legendreBigIntWithPtr(allocator: std.mem.Allocator, a: Int, p: Int, result: *Int) !void {
    var tmp = try p.clone();
    defer tmp.deinit();
    var tmp2 = try Int.initSet(allocator, 2);
    defer tmp2.deinit();

    try tmp.addScalar(&tmp, -1);
    try tmp.divFloor(&tmp2, &tmp, &tmp2);

    try powModulusBigIntWithPtr(allocator, a, tmp, p, result);
}

pub fn legendreBigInt(allocator: std.mem.Allocator, a: Int, p: Int) !Int {
    var tmp = try p.clone();
    defer tmp.deinit();
    var tmp2 = try Int.initSet(allocator, 2);

    try tmp.addScalar(&tmp, -1);
    try tmp.divFloor(&tmp2, &tmp, &tmp2);

    return powModulusBigInt(allocator, a, tmp, p);
}

pub fn tonelliShanksBigInt(allocator: std.mem.Allocator, n: Int, p: Int) !struct { Int, Int, bool } {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var result: struct { Int, Int, bool } = undefined;

    inline for (0..2) |i| {
        result[i] = try Int.init(allocator);
        errdefer {
            inline for (0..i) |j| result[j].deinit();
        }
    }
    errdefer {
        inline for (0..2) |i| result[i].deinit();
    }
    result[2] = false;

    var tmp = try legendreBigInt(arena.allocator(), n, p);

    var tmp2 = try Int.initSet(arena.allocator(), 1);

    if (!tmp.eql(tmp2))
        return result;

    result[2] = true;

    // Factor out powers of 2 from p - 1
    var q = try p.cloneWithDifferentAllocator(arena.allocator());

    try q.addScalar(&p, -1);

    var s = try Int.initSet(arena.allocator(), 0);

    try tmp2.set(2);
    while (q.isEven()) {
        try q.divFloor(&tmp, &q, &tmp2);
        try s.addScalar(&s, 1);
    }

    try tmp2.set(1);

    var tmp3 = try Int.init(arena.allocator());

    if (s.eql(tmp2)) {
        try tmp3.set(4);
        try tmp2.addScalar(&p, 1);
        try tmp2.divFloor(
            &tmp,
            &tmp2,
            &tmp3,
        );
        const res = try powModulusBigInt(arena.allocator(), n, tmp2, p);

        try result[0].copy(res.toConst());
        try result[1].sub(&p, &res);

        result[2] = true;
        return result;
    }

    // Find a non-square z such as ( z | p ) = -1
    var z = try Int.initSet(arena.allocator(), 2);

    try legendreBigIntWithPtr(allocator, z, p, &tmp);
    try tmp2.addScalar(&p, -1);
    while (!tmp.eql(tmp2)) {
        try z.addScalar(&z, 1);

        try legendreBigIntWithPtr(allocator, z, p, &tmp);
    }

    var c = try powModulusBigInt(arena.allocator(), z, q, p);
    var t = try powModulusBigInt(arena.allocator(), n, q, p);
    var m = try s.clone();

    try tmp.addScalar(&q, 1);

    try tmp.shiftRight(&tmp, 1);

    var res = try powModulusBigInt(arena.allocator(), n, tmp, p);

    try tmp3.set(1);

    var i = try Int.initSet(arena.allocator(), 1);
    var b = try Int.initSet(arena.allocator(), 0);

    while (!t.eql(tmp3)) {
        try i.set(1);

        try multiplyModulusBigIntWithPtr(arena.allocator(), t, t, p, &z);

        try tmp2.addScalar(&m, -1);

        while (!z.eql(tmp3) and i.order(tmp2).compare(.lt)) {
            try i.addScalar(&i, 1);

            try multiplyModulusBigIntWithPtr(arena.allocator(), z, z, p, &z);
        }

        try tmp2.set(1);
        try tmp.sub(&m, &i);
        try tmp.addScalar(&tmp, -1);

        try b.shiftLeft(&tmp2, try tmp.to(usize));

        try powModulusBigIntWithPtr(arena.allocator(), c, b, p, &b);
        try multiplyModulusBigIntWithPtr(arena.allocator(), b, b, p, &c);
        try multiplyModulusBigIntWithPtr(arena.allocator(), t, c, p, &t);

        try m.copy(i.toConst());

        try multiplyModulusBigIntWithPtr(arena.allocator(), res, b, p, &res);
    }

    try result[0].copy(res.toConst());
    try result[1].sub(&p, &res);
    result[2] = true;

    return result;
}

pub fn tonelliShanks(n: u512, p: u512) struct { u512, u512, bool } {
    if (legendre(n, p) != 1) {
        return .{ 0, 0, false };
    }

    // Factor out powers of 2 from p - 1
    var q: u512 = p - 1;
    var s: u512 = 0;
    while (q % 2 == 0) {
        q = q / 2;
        s = s + 1;
    }

    if (s == 1) {
        const result = powModulus(n, (p + 1) / 4, p);
        return .{ result, p - result, true };
    }

    // Find a non-square z such as ( z | p ) = -1
    var z: u512 = 2;
    while (legendre(z, p) != p - 1) {
        z = z + 1;
    }

    var c = powModulus(z, q, p);
    var t = powModulus(n, q, p);
    var m = s;
    var result = powModulus(n, (q + 1) >> 1, p);

    while (t != 1) {
        var i: u512 = 1;
        z = multiplyModulus(t, t, p);
        while (z != 1 and i < m - 1) {
            i = i + 1;
            z = multiplyModulus(z, z, p);
        }

        const b = powModulus(c, @as(u512, 1) << @intCast(m - i - 1), p);
        c = multiplyModulus(b, b, p);
        t = multiplyModulus(t, c, p);
        m = i;
        result = multiplyModulus(result, b, p);
    }
    return .{ result, p - result, true };
}

pub fn extendedGCDBigInt(allocator: std.mem.Allocator, self: *const Int, other: *const Int) !struct { gcd: Int, x: Int, y: Int } {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var s = [_]Int{ try Int.initSet(arena.allocator(), 0), try Int.initSet(arena.allocator(), 1) };
    var t = [_]Int{ try Int.initSet(arena.allocator(), 1), try Int.initSet(arena.allocator(), 0) };
    var r = [_]Int{ try other.cloneWithDifferentAllocator(arena.allocator()), try self.cloneWithDifferentAllocator(arena.allocator()) };

    var q_tmp = try Int.init(arena.allocator());
    var r_tmp = try Int.init(arena.allocator());

    while (!r[0].eqlZero()) {
        try q_tmp.divFloor(&r_tmp, &r[1], &r[0]);

        std.mem.swap(Int, &r[0], &r[1]);
        std.mem.swap(Int, &s[0], &s[1]);
        std.mem.swap(Int, &t[0], &t[1]);

        try r_tmp.mul(&q_tmp, &r[1]);
        try r[0].sub(&r[0], &r_tmp);

        try r_tmp.mul(&q_tmp, &s[1]);
        try s[0].sub(&s[0], &r_tmp);

        try r_tmp.mul(&q_tmp, &t[1]);
        try t[0].sub(&t[0], &r_tmp);
    }

    var gcd = try Int.init(allocator);
    errdefer gcd.deinit();

    var x = try Int.init(allocator);
    errdefer x.deinit();

    var y = try Int.init(allocator);
    errdefer y.deinit();

    if (!r[1].isPositive()) {
        r[1].negate();
        s[1].negate();
        t[1].negate();
    }

    try gcd.copy(r[1].toConst());
    try x.copy(s[1].toConst());
    try y.copy(t[1].toConst());

    return .{
        .gcd = gcd,
        .x = x,
        .y = y,
    };
}

pub fn extendedGCD(comptime T: type, self: T, other: T) struct { gcd: T, x: T, y: T } {
    var s = [_]T{ 0, 1 };
    var t = [_]T{ 1, 0 };
    var r = [_]T{ other, self };

    while (r[0] != 0) {
        const q = @divFloor(r[1], r[0]);
        std.mem.swap(T, &r[0], &r[1]);
        std.mem.swap(T, &s[0], &s[1]);
        std.mem.swap(T, &t[0], &t[1]);
        r[0] = r[0] - q * r[1];
        s[0] = s[0] - q * s[1];
        t[0] = t[0] - q * t[1];
    }

    return if (r[1] >= 0)
        .{ .gcd = r[1], .x = s[1], .y = t[1] }
    else
        .{ .gcd = -r[1], .x = -s[1], .y = -t[1] };
}

pub fn divModFloorSigned(num: i256, denominator: i256) !struct { i256, i256 } {
    if (denominator == 0) return error.DividedByZero;

    return .{
        @divFloor(num, denominator),
        @mod(num, denominator),
    };
}

pub fn divModFloor(comptime T: type, num: T, denominator: T) !struct { T, T } {
    if (denominator == 0) return error.DividedByZero;

    return .{ @divFloor(num, denominator), @mod(num, denominator) };
}

pub fn divRem(comptime T: type, num: T, denominator: T) !struct { T, T } {
    if (denominator == 0) return error.DividedByZero;

    return .{
        @divTrunc(num, denominator),
        @rem(num, denominator),
    };
}

pub fn safeDivBigIntV2(allocator: std.mem.Allocator, x: Int, y: Int) !Int {
    if (y.eqlZero()) return MathError.DividedByZero;

    var q = try Int.init(allocator);
    errdefer q.deinit();

    var r = try Int.init(allocator);
    defer r.deinit();

    try q.divFloor(&r, &x, &y);

    if (!r.eqlZero()) return MathError.SafeDivFailBigInt;

    return q;
}

pub fn divModBigInt(allocator: std.mem.Allocator, n: *const Int, m: *const Int, p: *const Int) !Int {
    var tmp = try Int.initSet(allocator, 1);
    defer tmp.deinit();

    var result = try Int.init(allocator);
    errdefer result.deinit();

    var igcdex_result = try extendedGCDBigInt(allocator, m, p);
    defer {
        igcdex_result.gcd.deinit();
        igcdex_result.x.deinit();
        igcdex_result.y.deinit();
    }

    if (!igcdex_result.gcd.eql(tmp)) {
        return MathError.DivModIgcdexNotZero;
    }

    try tmp.mul(n, &igcdex_result.x);
    try tmp.divFloor(&result, &tmp, p);

    return result;
}

pub fn divMod(comptime T: type, n: T, m: T, p: T) !T {
    const igcdex_result = extendedGCD(T, m, p);

    if (igcdex_result.gcd != 1) {
        return MathError.DivModIgcdexNotZero;
    }

    return @mod(n * igcdex_result.x, p);
}

/// Performs integer division between x and y; fails if x is not divisible by y.
pub fn safeDivBigInt(x: i512, y: i512) !i512 {
    if (y == 0) {
        return MathError.DividedByZero;
    }

    const result = try divModFloor(i512, x, y);

    if (result[1] != 0) {
        return MathError.SafeDivFailBigInt;
    }

    return result[0];
}

pub fn isPrimeU64(allocator: std.mem.Allocator, n: Int) !bool {
    var n_c = try n.clone();
    defer n_c.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var i = try Int.initSet(allocator, 2);
    defer i.deinit();

    var sqrt_n = try Int.init(allocator);
    defer sqrt_n.deinit();

    try sqrt_n.sqrt(&n_c);

    while (i.order(sqrt_n).compare(.lte)) {
        try tmp.divFloor(&n_c, &n, &i);

        if (n_c.eqlZero()) break;

        try i.addScalar(&i, 1);
    }

    if (i.order(sqrt_n).compare(.gt))
        return true
    else
        return false;
}

pub fn isPrime(n: Int) bool {
    return starknet.fields.isPrimeStdBigInt(n);
}

pub fn trailingZeroesBigInt(n: Int) !usize {
    const i: usize = for (0.., n.limbs) |i, digit| {
        if (digit != 0) break i;
    } else 0;

    const zeros = @ctz(n.limbs[i]);
    return i * @bitSizeOf(std.math.big.Limb) + zeros;
}

// Ported from sympy implementation
// Simplified as a & p are nonnegative
// Asumes p is a prime number
pub fn isQuadResidue(allocator: std.mem.Allocator, a: Int, p: Int) !bool {
    if (p.eqlZero())
        return MathError.IsQuadResidueZeroPrime;

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var a_new = if (a.order(p).compare(.gte)) blk: {
        var a_c = try a.clone();
        errdefer a_c.deinit();
        try tmp.divFloor(&a_c, &a, &p);
        break :blk a_c;
    } else blk: {
        break :blk try a.clone();
    };
    defer a_new.deinit();

    var tmp2 = try Int.initSet(allocator, 3);
    defer tmp2.deinit();

    try tmp.set(2);

    if (a.order(tmp).compare(.lt) or p.order(tmp2).compare(.lt))
        return true;

    try tmp.addScalar(&p, -1);
    try tmp2.set(2);

    try tmp.divFloor(&tmp2, &tmp, &tmp2);

    try powModulusBigIntWithPtr(allocator, a_new, tmp, p, &tmp);

    try tmp2.set(1);

    return tmp.eql(tmp2);
}

// Adapted from sympy _sqrt_prime_power with k == 1
pub fn sqrtPrimePower(allocator: std.mem.Allocator, a: Int, p: Int) !?Int {
    if (p.eqlZero() or !isPrime(p)) {
        return null;
    }

    var result = try Int.init(allocator);
    errdefer result.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var tmp1 = try Int.init(allocator);
    defer tmp1.deinit();
    var tmp2 = try Int.init(allocator);
    defer tmp2.deinit();

    var two = try Int.initSet(allocator, 2);
    defer two.deinit();

    try tmp.divFloor(&result, &a, &p);
    if (p.eql(two))
        return result;

    try tmp.addScalar(&p, -1);
    try tmp2.divFloor(&tmp1, &tmp, &two);

    try powModulusBigIntWithPtr(allocator, result, tmp2, p, &tmp);
    try tmp2.set(1);

    if (!(a.order(two).compare(.lt) or tmp.eql(tmp2))) {
        result.deinit();
        return null;
    }

    try tmp1.set(4);

    try tmp.divFloor(&tmp2, &p, &tmp1);
    try tmp.set(3);

    if (tmp2.eql(tmp)) {
        try tmp.addScalar(&p, 1);
        try tmp2.set(4);
        try tmp1.divFloor(&tmp2, &tmp, &tmp2);
        try powModulusBigIntWithPtr(allocator, result, tmp1, p, &result);
        try tmp.sub(&p, &result);

        if (result.order(tmp).compare(.gt)) {
            try result.copy(tmp.toConst());
        }

        return result;
    }

    try tmp2.set(8);
    try tmp.divFloor(&tmp1, &p, &tmp2);
    try tmp2.set(5);

    if (tmp1.eql(tmp2)) {
        try tmp.addScalar(&p, -1);
        try tmp1.set(4);
        try tmp.divFloor(&tmp1, &tmp, &tmp1);

        try powModulusBigIntWithPtr(allocator, result, tmp, p, &tmp1);

        try tmp.set(1);

        // tmp1 is sign
        if (tmp1.eql(tmp)) {
            try tmp.addScalar(&p, 3);
            try tmp1.set(8);

            try tmp.divFloor(&tmp1, &tmp, &tmp1);

            try powModulusBigIntWithPtr(allocator, result, tmp, p, &result);

            try tmp.sub(&p, &result);

            if (result.order(tmp).compare(.gt)) {
                try result.copy(tmp.toConst());
            }

            return result;
        } else {
            try tmp1.addScalar(&p, -5);
            try tmp.set(8);
            try tmp.divFloor(&tmp1, &tmp1, &tmp);

            try tmp2.set(4);
            try tmp2.mul(&tmp2, &result);

            try powModulusBigIntWithPtr(allocator, tmp2, tmp, p, &tmp);

            // b==tmp
            try tmp1.mul(&result, &tmp);
            try tmp2.set(2);
            try tmp1.mul(&tmp1, &tmp2);
            try tmp.divFloor(&tmp2, &tmp1, &p);

            // x==tmp2
            try powModulusBigIntWithPtr(allocator, tmp2, two, p, &tmp);
            if (tmp.eql(result)) {
                try result.copy(tmp2.toConst());
                return result;
            }
        }
    }
    defer result.deinit();

    var val1, var val2, _ = try tonelliShanksBigInt(allocator, result, p);
    // if (!succ) {
    //     return null;
    // }

    if (val1.order(val2).compare(.lt)) {
        val2.deinit();
        return val1;
    }

    val1.deinit();
    return val2;
}

///Returns num_a^-1 mod p
pub fn mulInv(allocator: std.mem.Allocator, num_a: Int, p: Int) !Int {
    var result = try Int.initSet(allocator, 0);
    errdefer result.deinit();

    if (num_a.eqlZero())
        return result;

    var a = try num_a.clone();
    defer a.deinit();
    a.abs();

    var x_sign = blk: {
        var res = try Int.initSet(allocator, 0);
        errdefer res.deinit();
        if (!num_a.eqlZero()) if (num_a.isPositive()) try res.set(1) else try res.set(-1);
        break :blk res;
    };
    defer x_sign.deinit();

    var b = try p.clone();
    defer b.deinit();
    b.abs();

    var x = try Int.initSet(allocator, 1);
    defer x.deinit();
    var r = try Int.initSet(allocator, 0);
    defer r.deinit();

    var c = try Int.initSet(allocator, 0);
    defer c.deinit();
    var q = try Int.initSet(allocator, 0);
    defer q.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    while (!b.eqlZero()) {
        try q.divFloor(&c, &a, &b);

        try result.mul(&q, &r);
        try x.sub(&x, &result);
        std.mem.swap(Int, &r, &x);
        try tmp.copy(b.toConst());
        try b.copy(c.toConst());
        try a.copy(tmp.toConst());
    }

    try result.mul(&x, &x_sign);
    return result;
}

test "Helper: extendedGCD big" {
    const result = extendedGCD(i512, 12452004504504594952858248542859182495912, 20504205040);

    var self = try Int.initSet(std.testing.allocator, 12452004504504594952858248542859182495912);
    defer self.deinit();

    var other = try Int.initSet(std.testing.allocator, 20504205040);
    defer other.deinit();

    var res2 = try extendedGCDBigInt(std.testing.allocator, &self, &other);
    defer {
        res2.gcd.deinit();
        res2.x.deinit();
        res2.y.deinit();
    }

    try std.testing.expectEqual(result.gcd, try res2.gcd.to(i512));
    try std.testing.expectEqual(result.x, try res2.x.to(i512));
    try std.testing.expectEqual(result.y, try res2.y.to(i512));
}

test "Helper: tonelli-shanks ok" {
    const val = tonelliShanks(2, 113);

    var n = try Int.initSet(std.testing.allocator, 2);
    defer n.deinit();
    var p = try Int.initSet(std.testing.allocator, 113);
    defer p.deinit();

    var val2 = try tonelliShanksBigInt(std.testing.allocator, n, p);
    defer {
        inline for (0..2) |i| val2[i].deinit();
    }

    try std.testing.expectEqual(val[0], try val2[0].to(u512));
    try std.testing.expectEqual(val[1], try val2[1].to(u512));
    try std.testing.expectEqual(val[2], val2[2]);
}

test "Helper: SqrtPrimePower" {
    var n = try Int.initSet(std.testing.allocator, 25);
    defer n.deinit();

    var p = try Int.initSet(std.testing.allocator, 577);
    defer p.deinit();

    var result = (try sqrtPrimePower(std.testing.allocator, n, p)).?;
    defer result.deinit();

    try std.testing.expect(try result.to(u8) == 5);
}

test "Helper: SqrtPrimePower p is zero" {
    var n = try Int.initSet(std.testing.allocator, 1);
    defer n.deinit();
    var p = try Int.initSet(std.testing.allocator, 0);
    defer p.deinit();

    try std.testing.expect(try sqrtPrimePower(std.testing.allocator, n, p) == null);
}

test "Helper: SqrtPrimePower mod 8 is 5 sign not one" {
    var n = try Int.initSet(std.testing.allocator, 676);
    defer n.deinit();
    var p = try Int.initSet(std.testing.allocator, 9956234341095173);
    defer p.deinit();

    var result = (try sqrtPrimePower(std.testing.allocator, n, p)).?;
    defer result.deinit();

    try std.testing.expectEqual(try result.to(u64), 9956234341095147);
}

test "Helper: SqrtPrimePower mod 8 is 5 sign is one" {
    var n = try Int.initSet(std.testing.allocator, 130283432663);
    defer n.deinit();
    var p = try Int.initSet(std.testing.allocator, 743900351477);
    defer p.deinit();

    var result = (try sqrtPrimePower(std.testing.allocator, n, p)).?;
    defer result.deinit();

    try std.testing.expectEqual(try result.to(u64), 123538694848);
}
