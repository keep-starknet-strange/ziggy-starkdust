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

/// Global compilation flags for the project.
pub const build_options = struct {
    /// Whether tracing should be disabled globally. This prevents the
    /// user from enabling tracing via the command line but it might
    /// improve performance slightly.
    pub const trace_disable = true;
    /// The initial capacity of the buffer responsible for gathering execution trace
    /// data.
    pub const trace_initial_capacity: usize = 4096;
};

// *****************************************************************************
// *                     MAIN ENTRY POINT                                      *
// *****************************************************************************
pub fn main() !void {
    try cmd.run();
}
