const std = @import("std");
const MathError = @import("../../vm/error.zig").MathError;
const Int = std.math.big.int.Managed;

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
