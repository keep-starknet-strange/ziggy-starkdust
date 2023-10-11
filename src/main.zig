const std = @import("std");
const starknet_felt = @import("math/fields/starknet.zig");
const vm_core = @import("vm/core.zig");
const RunContext = @import("vm/run_context.zig").RunContext;

pub fn main() !void {
    // *****************************************************************************
    // *                        INITIALIZATION                                     *
    // *****************************************************************************
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    // Define a memory allocator.
    var allocator = std.heap.page_allocator;

    // Greetings message.
    try stdout.print("Runing Cairo VM...\n", .{});

    // Create a new VM instance.
    var vm = try vm_core.CairoVM.init(&allocator);
    defer vm.deinit(); // <-- This ensures that resources are freed when exiting the scope

    // Run a step.
    try vm.step();

    // Print the run context pc.
    try stdout.print("PC: {}\n", .{vm.run_context.pc});
    try stdout.print("AP: {}\n", .{vm.run_context.ap});
    try stdout.print("FP: {}\n", .{vm.run_context.fp});

    // *****************************************************************************
    // *               FREEING RESOURCES AND EXIT                                  *
    // *****************************************************************************
    try bw.flush();
}

// *****************************************************************************
// *                     VM TESTS                                              *
// *****************************************************************************

test "memory" {
    _ = @import("vm/memory/memory.zig");
    _ = @import("vm/memory/segments.zig");
}

test "relocatable" {
    _ = @import("vm/memory/relocatable.zig");
}

// *****************************************************************************
// *                     MATH TESTS                                            *
// *****************************************************************************

test "fields" {
    _ = @import("math/fields/fields.zig");
    _ = @import("math/fields/starknet.zig");
}
