// *****************************************************************************
// *                         CUSTOM LOGGING                                    *
// *****************************************************************************

// Core imports.
const std = @import("std");

// Local imports.
const DateTime = @import("time.zig").DateTime;

// Define a memory allocator.
// TODO: Make this configurable.
const allocator = std.heap.page_allocator;

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = args;
    const scope_prefix = "(" ++ switch (scope) {
        .cairo_zig, std.log.default_log_scope => @tagName(scope),
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ ")";

    // TODO: Error handling.
    const time_log = DateTime.now().format(&allocator) catch unreachable;
    defer allocator.free(time_log);
    // TODO: Error handling.
    const prefix = std.fmt.allocPrint(allocator, "time={s} level={s} {s} msg=", .{ time_log, level.asText(), scope_prefix }) catch unreachable;
    defer allocator.free(prefix);

    // Create a mutable slice
    // +1 for the newline
    var combined: []u8 = allocator.alloc(u8, prefix.len + format.len + 1) catch unreachable;
    defer allocator.free(combined);

    std.mem.copy(u8, combined[0..prefix.len], prefix);
    std.mem.copy(u8, combined[prefix.len .. prefix.len + format.len], format);
    combined[prefix.len + format.len] = '\n';

    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print("{s}", .{combined}) catch return; // Make sure format specifiers and arguments match
}
