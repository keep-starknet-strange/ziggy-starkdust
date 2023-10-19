// Core imports.
const std = @import("std");
const cmd = @import("cmd/cmd.zig");

// Local imports.
const customlogFn = @import("utils/log.zig").logFn;

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
    try cmd.run();
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

// *****************************************************************************
// *                     UTIL TESTS                                            *
// *****************************************************************************

test "util" {
    _ = @import("utils/log.zig");
    _ = @import("utils/time.zig");
}
