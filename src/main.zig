const std = @import("std");
const starknet_felt = @import("fields/starknet.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Runing Cairo VM...\n", .{});

    const a = starknet_felt.Felt252.one();
    const b = starknet_felt.Felt252.fromInteger(2);
    const c = a.add(b);

    try stdout.print("c = {}\n", .{c.toInteger()});

    try bw.flush();
}

test "memory" {
    _ = @import("memory/memory.zig");
    _ = @import("memory/segments.zig");
}

test "fields" {
    _ = @import("fields/fields.zig");
    _ = @import("fields/starknet.zig");
}

test "relocatable" {
    _ = @import("memory/relocatable.zig");
}
