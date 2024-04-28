const std = @import("std");

pub const BLOCK_LEN: usize = 16;

fn shl(v: [4]u32, o: u32) [4]u32 {
    return .{ v[0] >> @intCast(o), v[1] >> @intCast(o), v[2] >> @intCast(o), v[3] >> @intCast(o) };
}

fn shr(v: [4]u32, o: u32) [4]u32 {
    return .{ v[0] << @intCast(o), v[1] << @intCast(o), v[2] << @intCast(o), v[3] << @intCast(o) };
}

fn orf(a: [4]u32, b: [4]u32) [4]u32 {
    return .{ a[0] | b[0], a[1] | b[1], a[2] | b[2], a[3] | b[3] };
}

fn xor(a: [4]u32, b: [4]u32) [4]u32 {
    return .{ a[0] ^ b[0], a[1] ^ b[1], a[2] ^ b[2], a[3] ^ b[3] };
}

fn add(a: [4]u32, b: [4]u32) [4]u32 {
    return .{
        @addWithOverflow(a[0], b[0])[0],
        @addWithOverflow(a[1], b[1])[0],
        @addWithOverflow(a[2], b[2])[0],
        @addWithOverflow(a[3], b[3])[0],
    };
}

fn sha256load(v2: [4]u32, v3: [4]u32) [4]u32 {
    return .{ v3[3], v2[0], v2[1], v2[2] };
}

fn sha256swap(v0: [4]u32) [4]u32 {
    return .{ v0[2], v0[3], v0[0], v0[1] };
}

fn sigma0x4(x: [4]u32) [4]u32 {
    const t1 = orf(shl(x, 7), shr(x, 25));
    const t2 = orf(shl(x, 18), shr(x, 14));
    const t3 = shl(x, 3);
    return xor(xor(t1, t2), t3);
}

fn sha256msg1(v0: [4]u32, v1: [4]u32) [4]u32 {
    // sigma 0 on vectors
    return add(v0, sigma0x4(sha256load(v0, v1)));
}

fn rotr(x: u32, n: u32) u32 {
    return (x >> @intCast(n % 32)) | (x << @intCast((32 - n) % 32));
}

fn sigma1(a: u32) u32 {
    return rotr(a, 17) ^ rotr(a, 19) ^ (a >> 10);
}

fn sha256msg2(v4: [4]u32, v3: [4]u32) [4]u32 {
    const x3, const x2, const x1, const x0 = v4;
    const w15, const w14, _, _ = v3;

    const w16 = @addWithOverflow(x0, sigma1(w14))[0];
    const w17 = @addWithOverflow(x1, sigma1(w15))[0];
    const w18 = @addWithOverflow(x2, sigma1(w16))[0];
    const w19 = @addWithOverflow(x3, sigma1(w17))[0];

    return .{ w19, w18, w17, w16 };
}

fn bigSigma0(a: u32) u32 {
    return rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
}
fn bigSigma1(a: u32) u32 {
    return rotr(a, 6) ^ rotr(a, 11) ^ rotr(a, 25);
}

fn bool3ary202(a: u32, b: u32, c: u32) u32 {
    return c ^ (a & (b ^ c));
}
fn bool3ary232(a: u32, b: u32, c: u32) u32 {
    return (a & b) ^ (a & c) ^ (b & c);
}

fn sha256DigestRoundX2(cdgh: [4]u32, abef: [4]u32, wk: [4]u32) [4]u32 {
    _, _, const wk1, const wk0 = wk;
    const a0, const b0, const e0, const f0 = abef;
    const c0, const d0, const g0, const h0 = cdgh;

    // a round
    var x0 = bigSigma1(e0);
    x0 = @addWithOverflow(x0, bool3ary202(e0, f0, g0))[0];
    x0 = @addWithOverflow(x0, wk0)[0];
    x0 = @addWithOverflow(x0, h0)[0];

    var y0 = bigSigma0(a0);
    y0 = @addWithOverflow(y0, bool3ary232(a0, b0, c0))[0];

    const a1, const b1, const c1, const d1, const e1, const f1, const g1, const h1 = .{
        @addWithOverflow(x0, y0)[0],
        a0,
        b0,
        c0,
        @addWithOverflow(x0, d0)[0],
        e0,
        f0,
        g0,
    };

    // a round
    var x1 = bigSigma1(e1);
    x1 = @addWithOverflow(bool3ary202(e1, f1, g1), x1)[0];
    x1 = @addWithOverflow(wk1, x1)[0];
    x1 = @addWithOverflow(h1, x1)[0];

    var y1 = bigSigma0(a1);
    y1 = @addWithOverflow(y1, bool3ary232(a1, b1, c1))[0];

    const a2, const b2, _, _, const e2, const f2, _, _ = .{
        @addWithOverflow(x1, y1)[0],
        a1,
        b1,
        c1,
        @addWithOverflow(x1, d1)[0],
        e1,
        f1,
        g1,
    };

    return .{ a2, b2, e2, f2 };
}

/// Constants necessary for SHA-256 family of digests.
pub const K32: [64]u32 = .{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

/// Constants necessary for SHA-256 family of digests.
pub const K32X4: [16][4]u32 = .{
    .{ K32[3], K32[2], K32[1], K32[0] },
    .{ K32[7], K32[6], K32[5], K32[4] },
    .{ K32[11], K32[10], K32[9], K32[8] },
    .{ K32[15], K32[14], K32[13], K32[12] },
    .{ K32[19], K32[18], K32[17], K32[16] },
    .{ K32[23], K32[22], K32[21], K32[20] },
    .{ K32[27], K32[26], K32[25], K32[24] },
    .{ K32[31], K32[30], K32[29], K32[28] },
    .{ K32[35], K32[34], K32[33], K32[32] },
    .{ K32[39], K32[38], K32[37], K32[36] },
    .{ K32[43], K32[42], K32[41], K32[40] },
    .{ K32[47], K32[46], K32[45], K32[44] },
    .{ K32[51], K32[50], K32[49], K32[48] },
    .{ K32[55], K32[54], K32[53], K32[52] },
    .{ K32[59], K32[58], K32[57], K32[56] },
    .{ K32[63], K32[62], K32[61], K32[60] },
};

fn schedule(v0: [4]u32, v1: [4]u32, v2: [4]u32, v3: [4]u32) [4]u32 {
    const t1 = sha256msg1(v0, v1);
    const t2 = sha256load(v2, v3);
    const t3 = add(t1, t2);
    return sha256msg2(t3, v3);
}

fn rounds4(abef: *[4]u32, cdgh: *[4]u32, rest: [4]u32, i: u32) void {
    const t1 = add(rest, K32X4[i]);
    cdgh.* = sha256DigestRoundX2(cdgh.*, abef.*, t1);
    const t2 = sha256swap(t1);
    abef.* = sha256DigestRoundX2(abef.*, cdgh.*, t2);
}

fn scheduleRounds4(
    abef: *[4]u32,
    cdgh: *[4]u32,
    w0: [4]u32,
    w1: [4]u32,
    w2: [4]u32,
    w3: [4]u32,
    w4: *[4]u32,
    i: u32,
) void {
    w4.* = schedule(w0, w1, w2, w3);
    rounds4(abef, cdgh, w4.*, i);
}

/// Process a block with the SHA-256 algorithm.
fn sha256DigestBlockU32(state: *[8]u32, block: [16]u32) void {
    var abef = [_]u32{ state[0], state[1], state[4], state[5] };
    var cdgh = [_]u32{ state[2], state[3], state[6], state[7] };

    // Rounds 0..64
    var w0 = [_]u32{ block[3], block[2], block[1], block[0] };
    var w1 = [_]u32{ block[7], block[6], block[5], block[4] };
    var w2 = [_]u32{ block[11], block[10], block[9], block[8] };
    var w3 = [_]u32{ block[15], block[14], block[13], block[12] };
    var w4: [4]u32 = undefined;

    rounds4(&abef, &cdgh, w0, 0);
    rounds4(&abef, &cdgh, w1, 1);
    rounds4(&abef, &cdgh, w2, 2);
    rounds4(&abef, &cdgh, w3, 3);
    scheduleRounds4(&abef, &cdgh, w0, w1, w2, w3, &w4, 4);
    scheduleRounds4(&abef, &cdgh, w1, w2, w3, w4, &w0, 5);
    scheduleRounds4(&abef, &cdgh, w2, w3, w4, w0, &w1, 6);
    scheduleRounds4(&abef, &cdgh, w3, w4, w0, w1, &w2, 7);
    scheduleRounds4(&abef, &cdgh, w4, w0, w1, w2, &w3, 8);
    scheduleRounds4(&abef, &cdgh, w0, w1, w2, w3, &w4, 9);
    scheduleRounds4(&abef, &cdgh, w1, w2, w3, w4, &w0, 10);
    scheduleRounds4(&abef, &cdgh, w2, w3, w4, w0, &w1, 11);
    scheduleRounds4(&abef, &cdgh, w3, w4, w0, w1, &w2, 12);
    scheduleRounds4(&abef, &cdgh, w4, w0, w1, w2, &w3, 13);
    scheduleRounds4(&abef, &cdgh, w0, w1, w2, w3, &w4, 14);
    scheduleRounds4(&abef, &cdgh, w1, w2, w3, w4, &w0, 15);

    const a, const b, const e, const f = abef;
    const c, const d, const g, const h = cdgh;

    state[0] = @addWithOverflow(state[0], a)[0];
    state[1] = @addWithOverflow(state[1], b)[0];
    state[2] = @addWithOverflow(state[2], c)[0];
    state[3] = @addWithOverflow(state[3], d)[0];
    state[4] = @addWithOverflow(state[4], e)[0];
    state[5] = @addWithOverflow(state[5], f)[0];
    state[6] = @addWithOverflow(state[6], g)[0];
    state[7] = @addWithOverflow(state[7], h)[0];
}

pub fn compress(state: *[8]u32, blocks: []const [64]u8) void {
    var block_u32 = [_]u32{0} ** BLOCK_LEN;
    block_u32[0] = 0;
    // since LLVM can't properly use aliasing yet it will make
    // unnecessary state stores without this copy
    var state_cpy = state.*;

    for (blocks) |block| {
        for (0.., &block_u32) |i, *o| {
            const chunk = block[i * 4 .. (i + 1) * 4];
            o.* = std.mem.readInt(u32, chunk[0..4], .big);
        }

        sha256DigestBlockU32(&state_cpy, block_u32);
    }
    state.* = state_cpy;
}
