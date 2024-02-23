const std = @import("std");
const ProgramJson = @import("vm/types/programjson.zig").ProgramJson;
const CairoVM = @import("vm/core.zig").CairoVM;
const CairoRunner = @import("vm/runners/cairo_runner.zig").CairoRunner;

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // Given
    const allocator = gpa.allocator();

    const cairo_programs = [_]struct {
        pathname: []const u8,
        layout: []const u8,
    }{
        .{ .pathname = "cairo_programs/factorial.json", .layout = "plain" },
        .{ .pathname = "cairo_programs/fibonacci.json", .layout = "plain" },
        .{ .pathname = "cairo_programs/bitwise_builtin_test.json", .layout = "all_cairo" },
        .{ .pathname = "cairo_programs/assert_lt_felt.json", .layout = "all_cairo" },
    };

    var ok_count: usize = 0;
    var fail_count: usize = 0;
    var progress = std.Progress{
        .dont_print_on_dumb = true,
    };
    const root_node = progress.start("Test", cairo_programs.len);
    const have_tty = progress.terminal != null and
        (progress.supports_ansi_escape_codes or progress.is_windows_terminal);

    for (cairo_programs, 0..) |test_cairo_program, i| {
        var test_node = root_node.start(test_cairo_program.pathname, 0);
        test_node.activate();
        progress.refresh();
        if (!have_tty) {
            std.debug.print("{d}/{d} {s}... \n", .{ i + 1, cairo_programs.len, test_cairo_program.pathname });
        }
        const result = cairo_run(allocator, test_cairo_program.pathname, test_cairo_program.layout);
        if (result) |_| {
            ok_count += 1;
            test_node.end();
            if (!have_tty) std.debug.print("OK\n", .{});
        } else |err| {
            fail_count += 1;
            progress.log("FAIL ({s})\n", .{@errorName(err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            test_node.end();
        }
    }

    root_node.end();

    if (ok_count == cairo_programs.len) {
        std.debug.print("All {d} tests passed.\n", .{ok_count});
    } else {
        std.debug.print("{d} passed; {d} failed.\n", .{ ok_count, fail_count });
    }
}

pub fn cairo_run(allocator: std.mem.Allocator, pathname: []const u8, layout: []const u8) !void {
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.realpath(pathname, &buffer);

    var parsed_program = try ProgramJson.parseFromFile(allocator, path);
    defer parsed_program.deinit();

    const instructions = try parsed_program.value.readData(allocator);

    const vm = try CairoVM.init(
        allocator,
        .{},
    );

    // when
    var runner = try CairoRunner.init(
        allocator,
        parsed_program.value,
        layout,
        instructions,
        vm,
        false,
    );
    defer runner.deinit();
    const end = try runner.setupExecutionState();
    errdefer std.debug.print("failed on step: {}\n", .{runner.vm.current_step});

    // then
    try runner.runUntilPC(end);
    try runner.endRun();
}
