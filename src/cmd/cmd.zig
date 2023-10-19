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

// ************************************************************
// *                 GLOBAL VARIABLES                         *
// ************************************************************

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();

// ************************************************************
// *                    CLI OPTIONS                           *
// ************************************************************

var execute_proof_mode_option = cli.Option{
    .long_name = "proof-mode",
    .help = "Whether to run in proof mode or not.",
    .short_alias = 'p',
    .value = cli.OptionValue{ .bool = false },
    .required = false,
    .value_name = "Proof mode",
};

// ************************************************************
// *                    CLI APP                               *
// ************************************************************

// Define the CLI app.
var app = &cli.App{
    .name = "cairo-zig",
    .description = "Cairo Virtual Machine written in Zig.\nHighly experimental, use at your own risk.",
    .version = "0.0.1",
    .author = "StarkWare & Contributors",
    .subcommands = &.{
        &cli.Command{ .name = "execute", .help = "Execute a cairo program.", .description = 
        \\Execute a cairo program with the virtual machine.
        , .action = execute, .options = &.{
            &execute_proof_mode_option,
        } },
    },
};

/// Run the CLI app.
pub fn run() !void {
    return cli.run(app, gpa_allocator);
}

// ************************************************************
// *                       CLI COMMANDS                       *
// ************************************************************

// execute entrypoint
fn execute(_: []const []const u8) !void {
    std.log.debug("Runing Cairo VM...\n", .{});

    // Create a new VM instance.
    var vm = try vm_core.CairoVM.init(&gpa_allocator);
    defer vm.deinit(); // <-- This ensures that resources are freed when exiting the scope

    const address_1 = relocatable.Relocatable.new(0, 0);
    const encoded_instruction = relocatable.fromU64(0x14A7800080008000);

    // Write a value to memory.
    try vm.segments.memory.set(address_1, encoded_instruction);

    // Run a step.
    vm.step() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
}
