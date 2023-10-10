const std = @import("std");
const Allocator = std.mem.Allocator;
const banderwagon = @import("../banderwagon/banderwagon.zig");
const Element = banderwagon.Element;
const ElementNormalized = banderwagon.ElementMSM;
const Fr = banderwagon.Fr;

// This is an implementation of "Notes on MSMs with Precomputation" by Gottfried Herold.

const optimals: [3]struct { length: u64, value: u4 } = .{
    .{ .length = 10, .value = 4 },
    .{ .length = 100, .value = 6 },
    .{ .length = std.math.maxInt(u64), .value = 8 },
};

// msm computes the multi-scalar multiplication of scalars_mont and basis. It automatically
// select the optimal window size.
pub fn msm(base_allocator: Allocator, basis: []const ElementNormalized, scalars_mont: []const Fr) !Element {
    const c: u4 = inline for (optimals) |optimal| {
        if (basis.len <= optimal.length) {
            break optimal.value;
        }
    };

    return msmWithWindowSize(base_allocator, c, basis, scalars_mont);
}

// msmWithWindowSize computes the multi-scalar multiplication of scalars_mont and basis using a specific window size.
// Usually clients should be using `msm` function instead to calculate this automatically.
pub fn msmWithWindowSize(base_allocator: Allocator, c: u4, basis: []const ElementNormalized, scalars_mont: []const Fr) !Element {
    const num_windows = std.math.divCeil(u8, Fr.BitSize, c) catch unreachable;
    const num_buckets = @as(u16, 1) << (c - 1);

    std.debug.assert(basis.len >= scalars_mont.len);

    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    var scalars_windows = try signedDigitDecomposition(allocator, c, num_windows, scalars_mont);

    var result: ?Element = null;
    var buckets = try allocator.alloc(?Element, num_buckets);
    @memset(buckets, null);

    for (0..num_windows) |w| {
        // Accumulate in buckets.
        for (0..buckets.len) |i| {
            buckets[i] = null;
        }
        for (0..scalars_mont.len) |i| {
            var scalar_window = scalars_windows[i + w * scalars_mont.len];
            if (scalar_window == 0) {
                continue;
            }

            var adj_basis: ElementNormalized = basis[i];
            if (scalar_window < 0) {
                adj_basis = ElementNormalized.neg(basis[i]);
                scalar_window = -scalar_window;
            }
            const bucket_idx = @as(usize, @intCast(scalar_window)) - 1;
            if (buckets[bucket_idx] == null) {
                buckets[bucket_idx] = Element.identity();
            }
            buckets[bucket_idx] = Element.mixedMsmAdd(buckets[bucket_idx].?, adj_basis);
        }

        // Aggregate buckets.
        var window_aggr: ?Element = null;
        var sum: ?Element = null;
        for (0..buckets.len) |i| {
            if (window_aggr == null and buckets[buckets.len - 1 - i] == null) {
                continue;
            }
            if (window_aggr == null) {
                window_aggr = buckets[buckets.len - 1 - i];
                sum = buckets[buckets.len - 1 - i];
                continue;
            }
            if (buckets[buckets.len - 1 - i] != null) {
                sum.?.add(sum.?, buckets[buckets.len - 1 - i].?);
            }
            window_aggr.?.add(window_aggr.?, sum.?);
        }

        // Aggregate into the final result.
        if (result != null) {
            for (0..c) |_| {
                result.?.double(result.?);
            }
        }
        if (window_aggr != null) {
            if (result == null) {
                result = window_aggr.?;
            } else {
                result.?.add(result.?, window_aggr.?);
            }
        }
    }

    return result orelse Element.identity();
}

fn signedDigitDecomposition(arena: Allocator, c: u4, num_windows: u8, scalars_mont: []const Fr) ![]i16 {
    const window_mask = (@as(u16, 1) << c) - 1;
    var scalars_windows = try arena.alloc(i16, scalars_mont.len * num_windows);

    for (0..scalars_mont.len) |i| {
        const scalar = scalars_mont[i].toInteger();
        var carry: u1 = 0;
        for (0..num_windows) |j| {
            const curr_window = @as(u16, @intCast((scalar >> @as(u8, @intCast(j * c))) & window_mask)) + carry;
            carry = 0;
            if (curr_window >= @as(u16, 1) << (c - 1)) {
                std.debug.assert(j != num_windows - 1);
                scalars_windows[(num_windows - 1 - j) * scalars_mont.len + i] = @as(i16, @intCast(curr_window)) - (@as(i16, 1) << c);
                carry = 1;
            } else {
                scalars_windows[(num_windows - 1 - j) * scalars_mont.len + i] = @as(i16, @intCast(curr_window));
            }
        }
    }

    return scalars_windows;
}

test "correctness" {
    const crs = @import("../crs/crs.zig");
    var xcrs = try crs.CRS.init(std.testing.allocator);
    defer xcrs.deinit();

    var scalars: [crs.DomainSize]Fr = undefined;
    for (0..scalars.len) |i| {
        scalars[i] = Fr.fromInteger((i + 0x93434) *% 0x424242);
    }

    for (1..crs.DomainSize) |msm_length| {
        const msm_scalars = scalars[0..msm_length];

        var full_scalars: [crs.DomainSize]Fr = undefined;
        for (0..full_scalars.len) |i| {
            if (i < msm_length) {
                full_scalars[i] = msm_scalars[i];
                continue;
            }
            full_scalars[i] = Fr.zero();
        }
        const exp = xcrs.commitSlow(full_scalars);
        const got = try msm(std.testing.allocator, xcrs.Gs[0..msm_length], msm_scalars);

        try std.testing.expect(Element.equal(exp, got));
    }
}
