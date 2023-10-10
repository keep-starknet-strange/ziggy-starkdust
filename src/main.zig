const std = @import("std");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Runing Cairo VM...\n", .{});

    try bw.flush();
}

test "fields" {
    _ = @import("fields/fields.zig");
}
