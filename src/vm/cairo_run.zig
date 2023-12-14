const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const Config = @import("./config.zig").Config;
const CairoVM = @import("./core.zig").CairoVM;
const Program = @import("./types/program.zig").Program;
const CairoRunner = @import("./runners/cairo_runner.zig").CairoRunner;
const trace_context = @import("./trace_context.zig");
const RelocatedTraceEntry = trace_context.TraceContext.RelocatedTraceEntry;

/// Writes the relocated trace to specified destination.
///
/// # Arguments
///
/// - `relocated_trace`:  The trace of execution, relocated.
/// - `dest`: The destination file that the trace is to be written.
pub fn writeEncodedTrace(relocated_trace: []const RelocatedTraceEntry, dest: *std.fs.File.Writer) !void {
    for (relocated_trace) |entry| {
        try dest.writeInt(u64, try entry.ap.tryIntoU64(), .little);
        try dest.writeInt(u64, try entry.fp.tryIntoU64(), .little);
        try dest.writeInt(u64, try entry.pc.tryIntoU64(), .little);
    }
}

/// Instruments the `CairoRunner` to initialize an execution of a cairo program based on Config params.
///
/// # Arguments
///
/// - `allocator`:  The allocator to initialize the CairoRunner and parsing of the program json.
/// - `config`: The config struct that defines the params that the CairoRunner uses to instantiate the vm state for running.
pub fn runConfig(allocator: Allocator, config: Config) !void {
    const vm = try CairoVM.init(
        allocator,
        config,
    );

    const parsed_program = try Program.parseFromFile(allocator, config.filename);
    const instructions = try parsed_program.value.readData(allocator);
    defer parsed_program.deinit();

    var runner = try CairoRunner.init(allocator, parsed_program.value, instructions, vm, config.proof_mode);
    defer runner.deinit();
    const end = try runner.setupExecutionState();
    try runner.runUntilPC(end);
    try runner.endRun();
    // TODO readReturnValues necessary for builtins

    if (config.output_trace) |trace_path| {
        const relocated_trace = try runner.consolidateTrace();

        const trace_file = try std.fs.cwd().createFile(trace_path, .{});
        defer trace_file.close();

        var trace_writer = trace_file.writer();
        try writeEncodedTrace(relocated_trace, &trace_writer);
    }
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

test "Fibonacci: can evaluate without runtime error" {

    // Given
    const allocator = std.testing.allocator;
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.realpath("cairo-programs/fibonacci.json", &buffer);

    var parsed_program = try Program.parseFromFile(allocator, path);
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
