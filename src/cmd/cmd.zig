// Core imports.
const std = @import("std");
// Dependencies imports.
const cli = @import("zig-cli");
// Local imports.
const vm_core = @import("../vm/core.zig");
const RunContext = @import("../vm/run_context.zig").RunContext;
const relocatable = @import("../vm/memory/relocatable.zig");
const Config = @import("../vm/config.zig").Config;
const build_options = @import("../build_options.zig");
const cairo_runner = @import("../vm/runners/cairo_runner.zig");
const CairoRunner = cairo_runner.CairoRunner;
const ProgramJson = @import("../vm/types/programjson.zig").ProgramJson;
const cairo_run = @import("../vm/cairo_run.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = std.heap.c_allocator;

// Configuration settings for the CLI.
var config = Config{
    .proof_mode = false,
    .enable_trace = false,
};

// Command-line option for enabling proof mode.
var execute_proof_mode_option = cli.Option{
    // The full name of the option.
    .long_name = "proof-mode",
    // Description of the option's purpose.
    .help = "Whether to run in proof mode or not.",
    // Short alias for the option.
    .short_alias = 'p',
    // Reference to the proof mode configuration.
    .value_ref = cli.mkRef(&config.proof_mode),
    // Indicates if the option is required.
    .required = false,
};

// Command-line option for specifying the filename.
var program_option = cli.Option{
    // The full name of the option.
    .long_name = "filename",
    // Description of the option's purpose.
    .help = "The location of the program to be evaluated.",
    // Short alias for the option.
    .short_alias = 'f',
    // Reference to the program filename.
    .value_ref = cli.mkRef(&config.filename),
    // Indicates if the option is required.
    .required = true,
};

// Command-line option for enabling trace mode.
var enable_trace = cli.Option{
    // The full name of the option.
    .long_name = "enable-trace",
    // Description of the option's purpose.
    .help = "Enable trace mode.",
    // Short alias for the option.
    .short_alias = 't',
    // Reference to the trace mode configuration.
    .value_ref = cli.mkRef(&config.enable_trace),
    // Indicates if the option is required.
    .required = false,
};

// Command-line option for specifying the output trace file.
var output_trace = cli.Option{
    // The full name of the option.
    .long_name = "output-trace",
    // Description of the option's purpose.
    .help = "File where the register execution cycles are written.",
    // Short alias for the option.
    .short_alias = 'o',
    // Reference to the output trace file.
    .value_ref = cli.mkRef(&config.output_trace),
    // Indicates if the option is required.
    .required = false,
};

// Command-line option for specifying the output memory file.
var output_memory = cli.Option{
    // The full name of the option.
    .long_name = "output-memory",
    // Description of the option's purpose.
    .help = "File where the memory post-execution is written.",
    // Short alias for the option.
    .short_alias = 'm',
    // Reference to the output memory file.
    .value_ref = cli.mkRef(&config.output_memory),
    // Indicates if the option is required.
    .required = false,
};

// Command-line option for specifying the memory layout.
var layout = cli.Option{
    // The full name of the option.
    .long_name = "layout",
    // Description of the option's purpose.
    .help = "The memory layout to use.",
    // Short alias for the option.
    .short_alias = 'l',
    // Reference to the memory layout.
    .value_ref = cli.mkRef(&config.layout),
    // Indicates if the option is required.
    .required = false,
};

// Define the CLI app
var app = &cli.App{
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
                &.{
                    // Name of the subcommand.
                    .name = "execute",
                    // Description of the subcommand.
                    .description = .{
                        // One-line summary of the subcommand.
                        .one_line = "Execute a cairo program with the virtual machine.",
                    },
                    // Options for the subcommand.
                    .options = &.{
                        &execute_proof_mode_option,
                        &layout,
                        &enable_trace,
                        &program_option,
                        &output_trace,
                        &output_memory,
                    },
                    // Action to be executed for the subcommand.
                    .target = .{ .action = .{ .exec = execute } },
                },
            },
        },
    },
};

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
    return cli.run(app, gpa_allocator);
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
    // std.log.debug("Running Cairo VM...\n", .{});
    if (build_options.trace_disable and config.enable_trace) {
        std.log.err("Tracing is disabled in this build.\n", .{});
        return UsageError.IncompatibleBuildOptions;
    }

    try cairo_run.runConfig(gpa_allocator, config);
}
