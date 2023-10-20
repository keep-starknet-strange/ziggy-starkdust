const std = @import("std");
const lib = @import("lib.zig");

// Automatically run all tests in files declared in the `lib.zig` file.
test {
    std.testing.log_level = std.log.Level.err;
    std.testing.refAllDecls(lib);
}
