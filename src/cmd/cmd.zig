// ************************************************************
// *                       IMPORTS                            *
// ************************************************************

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
const CairoRunner = @import("../vm/runners/cairo_runner.zig").CairoRunner;
const Program = @import("../vm/types/program.zig").Program;

// ************************************************************
// *                 GLOBAL VARIABLES                         *
// ************************************************************

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();

// ************************************************************
// *                    CLI OPTIONS                           *
// ************************************************************

var config = Config{ .proof_mode = false, .enable_trace = false };

var execute_proof_mode_option = cli.Option{
    .long_name = "proof-mode",
    .help = "Whether to run in proof mode or not.",
    .short_alias = 'p',
    .value_ref = cli.mkRef(&config.proof_mode),
    .required = false,
};

var program_option = cli.Option{
    .long_name = "filename",
    .help = "The location of the program to be evaluated.",
    .short_alias = 'f',
    .value_ref = cli.mkRef(&config.filename),
    .required = true,
};

var enable_trace = cli.Option{
    .long_name = "enable-trace",
    .help = "Enable trace mode",
    .short_alias = 't',
    .value_ref = cli.mkRef(&config.enable_trace),
    .required = false,
};

// ************************************************************
// *                    CLI APP                               *
// ************************************************************

// Define the CLI app.
var app = &cli.App{
    .name = "cairo-zig",
    .description =
    \\Cairo Virtual Machine written in Zig.
    \\Highly experimental, use at your own risk.
    ,
    .version = "0.0.1",
    .author = "StarkWare & Contributors",
    .subcommands = &.{
        &cli.Command{
            .name = "execute",
            .help = "Execute a cairo program.",
            .description =
            \\Execute a cairo program with the virtual machine.
            ,
            .action = execute,
            .options = &.{
                &execute_proof_mode_option,
                &enable_trace,
                &program_option
            },
        },
    },
};

/// Run the CLI app.
pub fn run() !void {
    return cli.run(
        app,
        gpa_allocator,
    );
}

// ************************************************************
// *                       CLI COMMANDS                       *
// ************************************************************

/// Errors that occur because the user misused the CLI.
const UsageError = error{
    /// Occurs when the user requests a config that is not supported by the current build.
    ///
    /// For example because execution traces are globally disabled.
    IncompatibleBuildOptions,
};

// execute entrypoint
fn execute(_: []const []const u8) !void {
    std.log.debug(
        "Running Cairo VM...\n",
        .{},
    );

    if (build_options.trace_disable and config.enable_trace) {
        std.log.err("Tracing is disabled in this build.\n", .{});
        return UsageError.IncompatibleBuildOptions;
    }

    var runner = try CairoRunner.initFromConfig(gpa_allocator, config);
    defer runner.deinit();
    var end = try runner.setupExecutionState();
    runner.runUntilPC(end);
}
