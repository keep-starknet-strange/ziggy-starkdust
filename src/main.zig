const std = @import("std");
const felt = @import("fields/felt_252.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Runing Cairo VM...\n", .{});

    const a = felt.StarkFelt252.one();
    const b = felt.StarkFelt252.fromInteger(2);
    const c = a.add(b);

    try stdout.print("c = {}\n", .{c.toInteger()});

    try bw.flush();
}

test "memory" {
    _ = @import("memory/memory.zig");
}

test "fields" {
    _ = @import("fields/fields.zig");
    _ = @import("fields/felt_252.zig");
}
