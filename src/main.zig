// Core imports.
const std = @import("std");
const builtin = @import("builtin");

// Local imports.
const starknet_felt = @import("math/fields/starknet.zig");
const vm_core = @import("vm/core.zig");
const RunContext = @import("vm/run_context.zig").RunContext;
const relocatable = @import("vm/memory/relocatable.zig");
const customlogFn = @import("log.zig").logFn;

// *****************************************************************************
// *                     GLOBAL CONFIGURATION                                  *
// *****************************************************************************

/// Standard library options.
pub const std_options = struct {
    /// Define the global log level.
    /// TODO: Make this configurable.
    pub const log_level = .debug;
    /// Define the log scope levels for each library.
    /// TODO: Make this configurable.
    pub const log_scope_levels = &[_]std.log.ScopeLevel{};
    // Define logFn to override the std implementation
    pub const logFn = customlogFn;
};

pub fn main() !void {
    // *****************************************************************************
    // *                        INITIALIZATION                                     *
    // *****************************************************************************

    // Define a memory allocator.
    var allocator = std.heap.page_allocator;

    // Greetings message.
    std.log.debug("Runing Cairo VM...\n", .{});

    // Create a new VM instance.
    var vm = try vm_core.CairoVM.init(&allocator);
    defer vm.deinit(); // <-- This ensures that resources are freed when exiting the scope

    const address_1 = relocatable.Relocatable.new(0, 0);
    const encoded_instruction = relocatable.fromU64(0x14A7800080008000);

    // Write a value to memory.
    try vm.segments.memory.set(address_1, encoded_instruction);

    // Run a step.
    vm.step() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
}

// *****************************************************************************
// *                     VM TESTS                                              *
// *****************************************************************************

test "vm" {
    _ = @import("vm/core.zig");
    _ = @import("vm/instructions.zig");
    _ = @import("vm/run_context.zig");
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
