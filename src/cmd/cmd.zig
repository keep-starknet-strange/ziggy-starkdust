// Core imports.
const std = @import("std");

const builtin = @import("builtin");
// Dependencies imports.
const cli = @import("zig-cli");
// Local imports.
const vm_core = @import("../vm/core.zig");
const RunContext = @import("../vm/run_context.zig").RunContext;
const relocatable = @import("../vm/memory/relocatable.zig");
const Config = @import("../vm/config.zig").Config;
const cairo_runner = @import("../vm/runners/cairo_runner.zig");
const CairoRunner = cairo_runner.CairoRunner;
const ProgramJson = @import("../vm/types/programjson.zig").ProgramJson;
const cairo_run = @import("../vm/cairo_run.zig");
const layout_lib = @import("../vm/types/layout.zig");
const errors = @import("../vm/error.zig");

// var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = std.heap.c_allocator;

// Configuration settings for the CLI.
const Args = struct {
    filename: []const u8 = undefined,
    trace_file: ?[]const u8 = null,
    print_output: bool = false,
    entrypoint: []const u8 = "main",
    memory_file: ?[]const u8 = null,
    layout: []const u8 = layout_lib.LayoutName.plain.toString(),
    proof_mode: bool = false,
    secure_run: ?bool = null,
    // require proof_mode=true
    air_public_input: ?[]const u8 = null,
    // requires proof_mode, trace_file, memory_file
    air_private_input: ?[]const u8 = null,

    allow_missing_builtins: ?bool = null,
};

var cfg: Args = .{};

/// Runs the Command-Line Interface application.
///
/// This function initializes and executes the CLI app with the provided configuration
/// and allocator, handling errors and the application's execution flow.
///
/// # Errors
///
/// Returns an error of type `UsageError` if there's a misuse of the CLI by the user,
/// such as requesting a configuration not supported by the current build,
/// for example, when execution traces are globally disabled.
pub fn run() !void {
    var r = try cli.AppRunner.init(global_allocator);

    // Command-line option for enabling proof mode.
    const proof_mode = cli.Option{
        // The full name of the option.
        .long_name = "proof-mode",
        // Description of the option's purpose.
        .help = "Whether to run in proof mode or not.",
        // Reference to the proof mode configuration.
        .value_ref = r.mkRef(&cfg.proof_mode),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for enabling secure run.
    const secure_run = cli.Option{
        // The full name of the option.
        .long_name = "secure-run",
        // Description of the option's purpose.
        .help = "Whether to run in secure mode or not.",
        // Reference to the proof mode configuration.
        .value_ref = r.mkRef(&cfg.secure_run),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for specifying the filename.
    const program_option = cli.Option{
        // The full name of the option.
        .long_name = "filename",
        // Description of the option's purpose.
        .help = "The location of the program to be evaluated.",
        // Reference to the program filename.
        .value_ref = r.mkRef(&cfg.filename),
        // Indicates if the option is required.
        .required = true,
    };

    // Command-line option for specifying the filename.
    const air_input_public = cli.Option{
        // The full name of the option.
        .long_name = "air-input-public",
        // Description of the option's purpose.
        .help = "The location where we wrote air input public.",
        // Reference to the program filename.
        .value_ref = r.mkRef(&cfg.air_public_input),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for specifying the filename.
    const air_input_private = cli.Option{
        // The full name of the option.
        .long_name = "air-input-private",
        // Description of the option's purpose.
        .help = "The location where we wrote air input private.",
        // Reference to the program filename.
        .value_ref = r.mkRef(&cfg.air_private_input),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for specifying the output trace file.
    const output_trace = cli.Option{
        // The full name of the option.
        .long_name = "trace-file",
        // Description of the option's purpose.
        .help = "File where the register execution cycles are written.",
        // Short alias for the option.
        .short_alias = 'o',
        // Reference to the output trace file.
        .value_ref = r.mkRef(&cfg.trace_file),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for specifying print output or not.
    const print_output = cli.Option{
        // The full name of the option.
        .long_name = "print-output",
        // Description of the option's purpose.
        .help = "Do we need to print output or not",
        // Reference to the output trace file.
        .value_ref = r.mkRef(&cfg.print_output),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for specifying entrypoint of program.
    const entrypoint = cli.Option{
        // The full name of the option.
        .long_name = "entrypoint",
        // Description of the option's purpose.
        .help = "Specifying entrypoint of program",
        // Reference to the output trace file.
        .value_ref = r.mkRef(&cfg.entrypoint),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for specifying the output memory file.
    const memory_file = cli.Option{
        // The full name of the option.
        .long_name = "memory-file",
        // Description of the option's purpose.
        .help = "File where the memory post-execution is written.",
        // Reference to the output memory file.
        .value_ref = r.mkRef(&cfg.memory_file),
        // Indicates if the option is required.
        .required = false,
    };

    // Command-line option for specifying the memory layout.
    const layout = cli.Option{
        // The full name of the option.
        .long_name = "layout",
        // Description of the option's purpose.
        .help = "The memory layout to use.",
        // Reference to the memory layout.
        .value_ref = r.mkRef(&cfg.layout),
        // Indicates if the option is required.
        .required = false,
    };

    // Define the CLI app
    var app = cli.App{
        // Version of the application.
        .version = "0.0.1",
        // Author information for the application.
        .author = "StarkWare & Contributors",
        // Configuration for the main command.
        .command = .{
            // Name of the main command.
            .name = "ziggy-starkdust",
            // Description of the main command.
            .description = .{
                // One-line summary of the main command.
                .one_line = "Cairo VM written in Zig.",
                // Detailed description of the main command.
                .detailed =
                \\Cairo Virtual Machine written in Zig.
                \\Highly experimental, use at your own risk.
                ,
            },
            // Target subcommand details.
            .target = .{
                // Subcommands of the main command.
                .subcommands = &.{
                    .{
                        // Name of the subcommand.
                        .name = "execute",
                        // Description of the subcommand.
                        .description = .{
                            // One-line summary of the subcommand.
                            .one_line = "Execute a cairo program with the virtual machine.",
                        },
                        // Options for the subcommand.
                        .options = &.{
                            proof_mode,
                            layout,
                            program_option,
                            output_trace,
                            secure_run,
                            memory_file,
                            air_input_public,
                            air_input_private,
                            print_output,
                            entrypoint,
                        },
                        // Action to be executed for the subcommand.
                        .target = .{ .action = .{ .exec = execute } },
                    },
                },
            },
        },
    };

    return r.run(&app);
}

/// Errors that occur because the user misused the CLI.
const UsageError = error{
    /// Occurs when the user requests a config that is not supported by the current build.
    ///
    /// For example because execution traces are globally disabled.
    IncompatibleBuildOptions,
};

/// Entry point for the execution of the Cairo Virtual Machine.
///
/// This function is responsible for executing the Cairo Virtual Machine based on the provided
/// configuration, allocator, and build options.
///
/// # Errors
///
/// Returns a `UsageError` if there's a misuse of the CLI, specifically if tracing is attempted
/// while it's disabled in the build.
fn execute() anyerror!void {
    try runProgram(global_allocator, cfg);
}

fn runProgram(allocator: std.mem.Allocator, _cfg: Args) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const trace_enabled = _cfg.trace_file != null or _cfg.air_public_input != null;

    const file = try std.fs.cwd().openFile(_cfg.filename, .{});
    defer file.close();

    // Read the entire file content into a buffer using the provided allocator
    const buffer = try file.readToEndAlloc(
        arena.allocator(),
        try file.getEndPos(),
    );
    defer arena.allocator().free(buffer);

    var runner = try cairo_run.cairoRun(
        arena.allocator(),
        buffer,
        .{
            .entrypoint = _cfg.entrypoint,
            .trace_enabled = trace_enabled,
            .relocate_mem = _cfg.memory_file != null or _cfg.air_public_input != null,
            .layout = _cfg.layout,
            .proof_mode = _cfg.proof_mode,
            .secure_run = _cfg.secure_run,
            .allow_missing_builtins = _cfg.allow_missing_builtins,
        },
        @constCast(&.{}),
    );
    defer runner.deinit(arena.allocator());
    defer runner.vm.segments.memory.deinitData(arena.allocator());

    if (_cfg.print_output) {
        var output_buffer = try std.ArrayList(u8).initCapacity(arena.allocator(), 100);
        output_buffer.appendSliceAssumeCapacity("Program Output:\n");

        try runner.vm.writeOutput(output_buffer.writer());
    }

    if (_cfg.trace_file) |trace_path| {
        const relocated_trace = runner.relocated_trace orelse return errors.TraceError.TraceNotRelocated;

        var writer: std.io.BufferedWriter(3 * 1024 * 1024, std.fs.File.Writer) = .{ .unbuffered_writer = undefined };

        const trace_file = try std.fs.cwd().createFile(trace_path, .{});
        defer trace_file.close();

        writer.unbuffered_writer = trace_file.writer();

        try cairo_run.writeEncodedTrace(relocated_trace, &writer);

        try writer.flush();
    }

    if (_cfg.memory_file) |memory_path| {
        var writer: std.io.BufferedWriter(5 * 1024 * 1024, std.fs.File.Writer) = .{ .unbuffered_writer = undefined };

        const memory_file = try std.fs.cwd().createFile(memory_path, .{});
        defer memory_file.close();

        writer.unbuffered_writer = memory_file.writer();

        try cairo_run.writeEncodedMemory(runner.relocated_memory.items, &writer);

        try writer.flush();
    }

    if (_cfg.air_public_input) |file_path| {
        var public_input = try runner.getAirPublicInput();
        defer public_input.deinit();

        const public_input_json = try public_input.serialize(arena.allocator());
        defer arena.allocator().free(public_input_json);

        var air_file = try std.fs.cwd().createFile(file_path, .{});
        defer air_file.close();

        try air_file.writeAll(public_input_json);
    }
}

test "RunOK" {
    for ([_][]const u8{
        "plain",
        // "small",
        // "dex",
        // "starknet",
        // "starknet_with_keccak",
        // "recursive_large_output",
        "all_cairo",
        // "all_solidity",
    }) |layout| {
        inline for ([_]bool{ false, true }) |memory_file| {
            inline for ([_]bool{ false, true }) |_trace_file| {
                inline for ([_]bool{ false, true }) |proof_mode| {
                    inline for ([_]bool{ false, true }) |print_out| {
                        inline for ([_]bool{ false, true }) |entrypoint| {
                            inline for ([_]bool{ false, true }) |air_input_public| {
                                var trace_file = _trace_file;

                                var _cfg: Args =
                                    .{
                                    .layout = layout,
                                    .air_public_input = if (air_input_public) "/dev/null" else null,
                                    .proof_mode = if (proof_mode) val: {
                                        trace_file = true;
                                        break :val true;
                                    } else false,
                                    .memory_file = if (memory_file) "/dev/null" else null,
                                    .trace_file = if (trace_file) "/dev/null" else null,
                                    .print_output = print_out,
                                    .filename = "cairo_programs/proof_programs/fibonacci.json",
                                };

                                if (entrypoint) _cfg.entrypoint = "main";

                                runProgram(
                                    std.testing.allocator,
                                    _cfg,
                                ) catch |err| {
                                    if (air_input_public and !proof_mode) return {} else return err;
                                };
                            }
                        }
                    }
                }
            }
        }
    }
}
