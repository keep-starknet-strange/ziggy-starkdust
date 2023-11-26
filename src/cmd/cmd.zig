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

    // Create a new VM instance.
    var vm = try vm_core.CairoVM.init(
        gpa_allocator,
        config,
    );
    defer vm.deinit(); // <-- This ensures that resources are freed when exiting the scope

    const address_1 = relocatable.Relocatable.new(
        0,
        0,
    );
    const encoded_instruction = relocatable.MaybeRelocatable.fromU64(0x14A7800080008000);

    // Write a value to memory.
    try vm.segments.memory.set(
        gpa_allocator,
        address_1,
        encoded_instruction,
    );
    defer vm.segments.memory.deinitData(gpa_allocator);

    // Run a step.
    vm.step(gpa_allocator) catch |err| {
        std.debug.print(
            "Error: {}\n",
            .{err},
        );
        return;
    };
}
