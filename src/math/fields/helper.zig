const std = @import("std");
const MathError = @import("../../vm/error.zig").MathError;

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

pub fn extendedGCD(self: i256, other: i256) struct { gcd: i256, x: i256, y: i256 } {
    var s = [_]i256{ 0, 1 };
    var t = [_]i256{ 1, 0 };
    var r = [_]i256{ other, self };

    while (r[0] != 0) {
        const q = @divFloor(r[1], r[0]);
        std.mem.swap(i256, &r[0], &r[1]);
        std.mem.swap(i256, &s[0], &s[1]);
        std.mem.swap(i256, &t[0], &t[1]);
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

pub fn divMod(n: i256, m: i256, p: i256) !i256 {
    const igcdex_result = try extendedGCD(m, p);
    if (igcdex_result.gcd != 1) {
        return MathError.DivModIgcdexNotZero;
    }

    var result = n * igcdex_result.x;
    if (result < 0) {
        result = result + p;
    }

    return result % p;
}

/// Performs integer division between x and y; fails if x is not divisible by y.
pub fn safeDivBigInt(x: i256, y: i256) !i256 {
    if (y == 0) {
        return MathError.DividedByZero;
    }

    const result = divModFloor(i256, x, y);

    if (result[1] != 0) {
        return MathError.SafeDivFailBigInt;
    }

    return result[0];
}
