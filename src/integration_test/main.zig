const std = @import("std");
const ProgramJson = @import("../vm/types/programjson.zig").ProgramJson;
const CairoVM = @import("../vm/core.zig").CairoVM;
const CairoRunner = @import("../vm/runners/cairo_runner.zig").CairoRunner;

const CairoRunInstruction = struct {
    pathname: []const u8,
    layout: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // Given
    const allocator = gpa.allocator();

    const cairo_programs = [_]CairoRunInstruction{
        .{ .pathname = "cairo_programs/factorial.json", .layout = "plain" },
        .{ .pathname = "cairo_programs/fibonacci.json", .layout = "plain" },
        .{ .pathname = "cairo_programs/bitwise_builtin_test.json", .layout = "all_cairo" },
    };

    for (cairo_programs) |cairo_program| {
        try cairo_run(allocator, cairo_program);
    }
}

pub fn cairo_run(allocator: std.mem.Allocator, cairo_program: CairoRunInstruction) !void {
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.realpath(cairo_program.pathname, &buffer);

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
        cairo_program.layout,
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
