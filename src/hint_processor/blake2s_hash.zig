const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
pub const IV = [8]u32{
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
};
const SIGMA = [_][16]usize{
    [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
    [_]usize{ 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 },
    [_]usize{ 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 },
    [_]usize{ 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 },
    [_]usize{ 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 },
    [_]usize{ 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 },
    [_]usize{ 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 },
    [_]usize{ 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 },
    [_]usize{ 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 },
    [_]usize{ 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 },
};
fn right_rot(value: u32, comptime n: u5) u32 {
    return (value >> n) | (value << (@as(u6, 32) - @as(u6, n)));
}
fn mix(a: u32, b: u32, c: u32, d: u32, m0: u32, m1: u32) struct { u32, u32, u32, u32 } {
    var a1 = a +% b +% m0;
    var d1 = right_rot(d ^ a1, 16);
    var c1 = c +% d1;
    var b1 = right_rot(b ^ c1, 12);
    a1 = a1 +% b1 +% m1;
    d1 = right_rot(d1 ^ a1, 8);
    c1 = c1 +% d1;
    b1 = right_rot(b1 ^ c1, 7);
    return .{ a1, b1, c1, d1 };
}
fn blake_round(state: std.ArrayList(u32), message: [16]u32, sigma: [16]usize) void {
    const state_items = state.items;
    state_items[0], state_items[4], state_items[8], state_items[12] = mix(
        state_items[0],
        state_items[4],
        state_items[8],
        state_items[12],
        message[sigma[0]],
        message[sigma[1]],
    );

    state_items[1], state_items[5], state_items[9], state_items[13] = mix(
        state_items[1],
        state_items[5],
        state_items[9],
        state_items[13],
        message[sigma[2]],
        message[sigma[3]],
    );
    state_items[2], state_items[6], state_items[10], state_items[14] = mix(
        state_items[2],
        state_items[6],
        state_items[10],
        state_items[14],
        message[sigma[4]],
        message[sigma[5]],
    );
    state_items[3], state_items[7], state_items[11], state_items[15] = mix(
        state_items[3],
        state_items[7],
        state_items[11],
        state_items[15],
        message[sigma[6]],
        message[sigma[7]],
    );
    state_items[0], state_items[5], state_items[10], state_items[15] = mix(
        state_items[0],
        state_items[5],
        state_items[10],
        state_items[15],
        message[sigma[8]],
        message[sigma[9]],
    );

    state_items[1], state_items[6], state_items[11], state_items[12] = mix(
        state_items[1],
        state_items[6],
        state_items[11],
        state_items[12],
        message[sigma[10]],
        message[sigma[11]],
    );
    state_items[2], state_items[7], state_items[8], state_items[13] = mix(
        state_items[2],
        state_items[7],
        state_items[8],
        state_items[13],
        message[sigma[12]],
        message[sigma[13]],
    );
    state_items[3], state_items[4], state_items[9], state_items[14] = mix(
        state_items[3],
        state_items[4],
        state_items[9],
        state_items[14],
        message[sigma[14]],
        message[sigma[15]],
    );
}
pub fn blake2s_compress(
    allocator: Allocator,
    h: [8]u32,
    message: [16]u32,
    t0: u32,
    t1: u32,
    f0: u32,
    f1: u32,
) !std.ArrayList(u32) {
    var state = std.ArrayList(u32).init(allocator);
    defer state.deinit();
    try state.appendSlice(&h);
    try state.appendSlice(&[8]u32{ IV[0], IV[1], IV[2], IV[3], IV[4] ^ t0, IV[5] ^ t1, IV[6] ^ f0, IV[7] ^ f1 });

    for (SIGMA) |sigma| {
        blake_round(state, message, sigma);
    }
    var new_state = std.ArrayList(u32).init(allocator);
    for (0..8) |i| {
        try new_state.append(h[i] ^ state.items[i] ^ state.items[8 + i]);
    }
    return new_state;
}

test "blake2s compress: test a" {
    const h = [8]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    };
    const message = [_]u32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const new_state = try blake2s_compress(testing.allocator, h, message, 2, 0, 4294967295, 0);
    defer new_state.deinit();
    try std.testing.expectEqualSlices(u32, &[8]u32{ 412110711, 3234706100, 3894970767, 982912411, 937789635, 742982576, 3942558313, 1407547065 }, new_state.items);
}

test "blake2s compress: test b" {
    const h = [8]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    };
    const message = [_]u32{ 456710651, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const new_state = try blake2s_compress(testing.allocator, h, message, 2, 0, 4294967295, 0);
    defer new_state.deinit();
    try std.testing.expectEqualSlices(u32, &[8]u32{ 1061041453, 3663967611, 2158760218, 836165556, 3696892209, 3887053585, 2675134684, 2201582556 }, new_state.items);
}

test "blake2s compress: test c" {
    const h = [8]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    };
    const message = [_]u32{
        1819043144, 1870078063, 6581362, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const new_state = try blake2s_compress(testing.allocator, h, message, 9, 0, 4294967295, 0);
    defer new_state.deinit();
    try std.testing.expectEqualSlices(u32, &[8]u32{ 939893662, 3935214984, 1704819782, 3912812968, 4211807320, 3760278243, 674188535, 2642110762 }, new_state.items);
}

test "blake2s compress: test d" {
    const h = [8]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    };
    const message = [_]u32{
        1819043144, 1870078063, 6581362, 274628678, 715791845, 175498643, 871587583, 0, 0, 0,
        0,          0,          0,       0,         0,         0,
    };
    const new_state = try blake2s_compress(testing.allocator, h, message, 28, 0, 4294967295, 0);
    defer new_state.deinit();
    try std.testing.expectEqualSlices(u32, &[8]u32{ 3980510537, 3982966407, 1593299263, 2666882356, 3288094120, 2682988286, 1666615862, 378086837 }, new_state.items);
}

test "blake2s compress: test e" {
    const h = [8]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    };
    const message = [_]u32{
        1819043144, 1870078063, 6581362,   274628678, 715791845, 175498643, 871587583, 635963558,
        557369694,  1576875962, 215769785, 0,         0,         0,         0,         0,
    };
    const new_state = try blake2s_compress(testing.allocator, h, message, 44, 0, 4294967295, 0);
    defer new_state.deinit();
    try std.testing.expectEqualSlices(u32, &[8]u32{ 3251785223, 1946079609, 2665255093, 3508191500, 3630835628, 3067307230, 3623370123, 656151356 }, new_state.items);
}

test "blake2s compress: test f" {
    const h = [8]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    };
    const message = [_]u32{
        1819043144, 1870078063, 6581362,   274628678, 715791845, 175498643, 871587583, 635963558,
        557369694,  1576875962, 215769785, 152379578, 585849303, 764739320, 437383930, 74833930,
    };
    const new_state = try blake2s_compress(testing.allocator, h, message, 64, 0, 4294967295, 0);
    defer new_state.deinit();
    try std.testing.expectEqualSlices(u32, &[8]u32{ 2593218707, 3238077801, 914875393, 3462286058, 4028447058, 3174734057, 2001070146, 3741410512 }, new_state.items);
}

test "blake2s compress: test g" {
    const h = [8]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225,
    };
    const message = [_]u32{
        11563522,  43535528,   653255322, 274628678, 73471943,  17549868, 87158958,  635963558,
        343656565, 1576875962, 215769785, 152379578, 585849303, 76473202, 437253230, 74833930,
    };
    const new_state = try blake2s_compress(testing.allocator, h, message, 64, 0, 4294967295, 0);
    defer new_state.deinit();
    try std.testing.expectEqualSlices(u32, &[8]u32{ 3496615692, 3252241979, 3771521549, 2125493093, 3240605752, 2885407061, 3962009872, 3845288240 }, new_state.items);
}
