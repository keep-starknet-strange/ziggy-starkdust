const std = @import("std");
const starknet_felt = @import("fields/starknet.zig");
const segments = @import("memory/segments.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Runing Cairo VM...\n", .{});

    // Define a memory allocator.
    const allocator = std.heap.page_allocator;

    // Initialize a memory segment manager.
    var memory_segment_manager = try segments.MemorySegmentManager.init(allocator);

    // Allocate a memory segment.
    _ = memory_segment_manager.addSegment();

    // Allocate another memory segment.
    _ = memory_segment_manager.addSegment();

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
