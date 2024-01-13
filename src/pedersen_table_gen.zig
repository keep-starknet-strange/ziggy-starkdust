/// Generating pedersen table for Felt252
/// All memory allocation is on arena allocator
/// code ported from starknet-crypto-codegen:
/// https://github.com/xJonathanLEI/starknet-rs/blob/0857bd6cd3bd34cbb06708f0a185757044171d8d/starknet-crypto-codegen/src/pedersen.rs
const std = @import("std");
const Felt252 = @import("./math/fields/starknet.zig").Felt252;
const AffinePoint = @import("./math/crypto/curve/ec_point.zig").AffinePoint;
const Allocator = std.mem.Allocator;
const curve_params = @import("./math/crypto/curve/curve_params.zig");

const final_block = "const AffinePoint = @import(\"../../curve/ec_point.zig\").AffinePoint;\n" ++
    "pub const CURVE_CONSTS_BITS: usize = {};";

fn lookupTable(allocator: Allocator, comptime bits: u32) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);

    try std.fmt.format(output.writer(), final_block, .{bits});

    try pushPoints(output.writer(), "P0", curve_params.PEDERSEN_P0, 248, bits);
    try pushPoints(output.writer(), "P1", curve_params.PEDERSEN_P1, 4, bits);
    try pushPoints(output.writer(), "P2", curve_params.PEDERSEN_P2, 248, bits);
    try pushPoints(output.writer(), "P3", curve_params.PEDERSEN_P3, 4, bits);

    return try output.toOwnedSlice();
}

fn pushPoint(writer: anytype, p: *AffinePoint) !void {
    const felt = ".{{\t\n\t.fe = [4]u64{{\n{},\n{},\n{},\n{},\n}},\n}},\n";

    try writer.writeAll(".{\n.x = ");
    try std.fmt.format(writer, felt, .{ p.x.fe[0], p.x.fe[1], p.x.fe[2], p.x.fe[3] });
    try writer.writeAll(".y = ");
    try std.fmt.format(writer, felt, .{ p.y.fe[0], p.y.fe[1], p.y.fe[2], p.y.fe[3] });
    try writer.writeAll(".infinity = false,\n},");
}

fn pushPoints(writer: anytype, name: []const u8, base: AffinePoint, comptime max_bits: u32, comptime bits: u32) !void {
    const full_chunks = max_bits / bits;
    const leftover_bits = max_bits % bits;
    const table_size_full = (1 << bits) - 1;
    const table_size_leftover = (1 << leftover_bits) - 1;
    const len = full_chunks * table_size_full + table_size_leftover;

    try std.fmt.format(writer, "pub const CURVE_CONSTS_{s}: [{d}]AffinePoint = .{{\n", .{ name, len });

    var bits_left: u32 = max_bits;
    var outer_point = base;

    while (bits_left > 0) {
        const eat_bits = @min(bits_left, bits);
        const table_size = (@as(u32, 1) << eat_bits) - 1;

        // Loop through each possible bit combination except zero
        var inner_point = outer_point;
        for (1..(table_size + 1)) |_| {
            try pushPoint(writer, &inner_point);
            inner_point.addAssign(&outer_point);
        }

        // Shift outer point #bits times
        bits_left -= eat_bits;
        inline for (0..bits) |_| {
            outer_point.doubleAssign();
        }
    }

    try writer.writeAll("};\n\n");
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try lookupTable(allocator, 4);

    var file = try std.fs.cwd().openFile("./src/math/crypto/pedersen/gen/constants.zig", .{ .mode = .write_only });

    try file.writer().writeAll(output);
}
