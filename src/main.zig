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

// *****************************************************************************
// *                     MAIN ENTRY POINT                                      *
// *****************************************************************************
pub fn main() !void {
    try cmd.run();
}
