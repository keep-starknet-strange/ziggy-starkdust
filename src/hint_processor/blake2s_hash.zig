const std = @import("std");
const Allocator = std.mem.Allocator;
pub const IV: [8]u32 = .{
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
};

fn blake_round(state: std.ArrayList(u32), message: [16]u32, sigma: [16]usize) std.ArrayList(u32) {}
pub fn blake2s_compress(
    allocator: Allocator,
    h: [8]u32,
    message: [16]u32,
    t0: u32,
    t1: u32,
    f0: u32,
    f1: u32,
) std.ArrayList(u32) {
    var result = std.ArrayList(u32).init(allocator);
    for (h) |h_i| {
        try result.append(h_i);
    }
    result.appendSlice([4]u32{
        IV[4] ^ t0,
        IV[5] ^ t1,
        IV[6] ^ f0,
        IV[7] ^ f1,
    });
}
