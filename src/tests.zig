const std = @import("std");
const lib = @import("lib.zig");
const cmd = @import("cmd/cmd.zig");

// Automatically run all tests in files declared in the `lib.zig` file.
test {
    std.testing.log_level = std.log.Level.err;
    std.testing.refAllDecls(lib);
    std.testing.refAllDecls(cmd);
}
