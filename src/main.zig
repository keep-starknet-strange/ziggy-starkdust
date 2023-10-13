const std = @import("std");
const starknet_felt = @import("math/fields/starknet.zig");
const vm_core = @import("vm/core.zig");
const RunContext = @import("vm/run_context.zig").RunContext;
const relocatable = @import("vm/memory/relocatable.zig");

pub fn main() !void {
    // *****************************************************************************
    // *                        INITIALIZATION                                     *
    // *****************************************************************************

    // Define a memory allocator.
    var allocator = std.heap.page_allocator;

    // Greetings message.
    std.debug.print("Runing Cairo VM...\n", .{});

    // Create a new VM instance.
    var vm = try vm_core.CairoVM.init(&allocator);
    defer vm.deinit(); // <-- This ensures that resources are freed when exiting the scope

    // Print the run context pc.
    std.debug.print("PC: {}\n", .{vm.run_context.pc});
    std.debug.print("AP: {}\n", .{vm.run_context.ap});
    std.debug.print("FP: {}\n", .{vm.run_context.fp});

    const address_1 = relocatable.Relocatable.new(0, 0);
    const value_1 = relocatable.newFromFelt(starknet_felt.Felt252.fromInteger(158745829));

    // Write a value to memory.
    try vm.segments.memory.set(address_1, value_1);

    const read_value = try vm.segments.memory.get(address_1);

    std.debug.print("Value: {}\n", .{read_value.felt.toInteger()});

    // Run a step.
    try vm.step();
}

// *****************************************************************************
// *                     VM TESTS                                              *
// *****************************************************************************

test "vm" {
    _ = @import("vm/core.zig");
    _ = @import("vm/instruction.zig");
}

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
