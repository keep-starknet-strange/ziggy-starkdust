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

/// Custom log function.
/// This function is used to log messages with a custom format.
/// The format is as follows:
///    time={time} level={level} ({scope}) msg={message}
/// Where:
/// - {time} is the current time in ISO 8601 format.
/// - {level} is the log level.
/// - {scope} is the scope of the log message.
/// - {message} is the message to log.
/// # Arguments
/// - `level` is the log level.
/// - `scope` is the scope of the log message.
/// - `format` is the format string.
/// - `args` are the arguments to the format string.
pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {

    // Capture the current time in UTC format.
    const utc_format = "YYYY-MM-DDTHH:mm:ss";
    const time_str = DateTime.now().formatAlloc(allocator, utc_format) catch unreachable;

    // Convert the log level and scope to string using @tagName.
    const level_str = @tagName(level);
    const scope_str = @tagName(scope);

    const stderr = std.io.getStdErr().writer();

    // Log the header
    _ = stderr.print("time={s} level={s} ({s}) msg=", .{ time_str, level_str, scope_str }) catch unreachable;

    // Log the main message
    nosuspend stderr.print(format, args) catch return;

    // Write a newline for better readability.
    nosuspend stderr.writeAll("\n") catch return;
}
