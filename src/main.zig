// Core imports.
const std = @import("std");
const cmd = @import("cmd/cmd.zig");

// Local imports.
const customlogFn = @import("utils/log.zig").logFn;

// *****************************************************************************
// *                     GLOBAL CONFIGURATION                                  *
// *****************************************************************************

/// Standard library options.
/// log_level and log_scope_levels make it configurable.
pub const std_options = .{
    .logFn = customlogFn,
    .log_level = .debug,
    .log_scope_levels = &[_]std.log.ScopeLevel{},
};

// *****************************************************************************
// *                     MAIN ENTRY POINT                                      *
// *****************************************************************************
pub fn main() !void {
    try cmd.run();
}
