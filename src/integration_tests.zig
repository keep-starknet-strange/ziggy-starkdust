const std = @import("std");
const ProgramJson = @import("vm/types/programjson.zig").ProgramJson;
const Program = @import("vm/types/program.zig").Program;
const CairoVM = @import("vm/core.zig").CairoVM;
const CairoRunner = @import("vm/runners/cairo_runner.zig").CairoRunner;
const HintProcessor = @import("./hint_processor/hint_processor_def.zig").CairoVMHintProcessor;

const CairoTestProgram = struct {
    pathname: []const u8,
    layout: []const u8,
    extensive_hints: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // Given
    const allocator = gpa.allocator();

    // Refactor: Handle command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var test_files_list: ?[]const u8 = null;
    if (args.len > 1) {
        // TODO: Parse command-line arguments more rigorously with a CLI utility
        test_files_list = args[1];
    }

    var cairo_programs: []CairoTestProgram = undefined; // This will be defined after reading from the test file or defaulting to all tests.

    // If there are specific tests to run, read them from the file.
    if (test_files_list) |list| {
        var file = try std.fs.cwd().openFile(list, .{});
        defer file.close();
        const fileSize = try file.getEndPos();
        const buffer = try allocator.alloc(u8, fileSize);
        defer allocator.free(buffer);

        const bytes_read = try file.read(buffer);
        // TODO add error handing here for empty file case
        if (bytes_read == 0) return;

        // Split the buffer by new lines and create cairo_programs array.
        // Split the buffer by new lines and collect lines into a vector because we can't get .len from an iterator.
        var lines = std.ArrayList([]const u8).init(allocator);
        defer lines.deinit(); // Ensure allocated memory is freed appropriately

        // Splitting the buffer into lines and adding them to 'lines' ArrayList.
        var splitIterator = std.mem.split(u8, buffer, "\n");
        while (splitIterator.next()) |line| {
            try lines.append(line);
        }

        // Now, lines.items gives us the array and lines.len gives us the count.
        cairo_programs = try allocator.alloc(CairoTestProgram, lines.items.len);

        for (lines.items, 0..) |line, i| {
            cairo_programs[i] = CairoTestProgram{
                .pathname = try std.fmt.allocPrint(allocator, "cairo_programs/{s}.json", .{line}),
                .layout = "all_cairo", // Assuming 'all_cairo' layout for simplicity; adjust if necessary.
                .extensive_hints = false,
            };
        }
    } else {
        // Default set of cairo_programs if no command line arguments are provided
        // this is just for demonstration purposes
        var temp_array = [_]CairoTestProgram{
            .{ .pathname = "cairo_programs/abs_value_array_compiled.json", .layout = "all_cairo" },
            // TODO: UnknownOp0 error
            // .{ .pathname = "cairo_programs/array_sum_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/assert_lt_felt.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/assert_250_bit_element_array_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/assert_le_felt_hint_compiled.json", .layout = "all_cairo" },
            // .{ .pathname = "cairo_programs/assert_le_felt_old_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/assert_nn_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/assert_not_zero_compiled.json", .layout = "all_cairo" },
            // TODO: merge bigint hint
            // .{ .pathname = "cairo_programs/bigint_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/big_struct_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/bitand_hint_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/bitwise_output_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/bitwise_builtin_test.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/bitwise_recursion_compiled.json", .layout = "all_cairo" },
            // TODO: merge blake hint
            // .{ .pathname = "cairo_programs/blake2s_felts.json", .layout = "all_cairo" },
            // .{ .pathname = "cairo_programs/blake2s_hello_world_hash.json", .layout = "all_cairo" },
            // .{ .pathname = "cairo_programs/blake2s_integration_tests.json", .layout = "all_cairo" },
            // TODO: implement cairo keccak
            // .{ .pathname = "cairo_programs/cairo_finalize_keccak_compiled.json", .layout = "all_cairo" },
            // .{ .pathname = "cairo_programs/cairo_finalize_keccak_block_size_1000.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/call_function_assign_param_by_name.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp1 error
            // .{ .pathname = "cairo_programs/chained_ec_op.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/common_signature.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp1 error
            // .{ .pathname = "cairo_programs/compare_arrays.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/compare_different_arrays.json", .layout = "all_cairo" },
            // TODO: NoDst error
            // .{ .pathname = "cairo_programs/compare_greater_array.json", .layout = "all_cairo" },
            // TODO: NoDst error
            // .{ .pathname = "cairo_programs/compare_lesser_array.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0
            // .{ .pathname = "cairo_programs/compute_doubling_slope_v2.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0
            // .{ .pathname = "cairo_programs/compute_slope_v2.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/dict.json", .layout = "all_cairo" },
            // TODO: RelocatableAdd error
            // .{ .pathname = "cairo_programs/dict_integration_tests.json", .layout = "all_cairo" },
            // TODO: RelocatableAdd error
            // .{ .pathname = "cairo_programs/dict_squash.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/dict_store_cast_ptr.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/dict_update.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/div_mod_n.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/ec_double_assign_new_x_v3.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/ec_double_slope.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/ec_double_v4.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/ec_negate.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp1 error
            // .{ .pathname = "cairo_programs/ec_op.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/ec_recover.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/ed25519_ec.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/ed25519_field.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/efficient_secp256r1_ec.json", .layout = "all_cairo" },
            // TODO: merge blake hint
            // .{ .pathname = "cairo_programs/example_blake2s.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/example_program.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/factorial.json", .layout = "plain" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/fast_ec_add_v2.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/fast_ec_add_v3.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/field_arithmetic.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/fibonacci.json", .layout = "plain" },
            // TODO: FailedToComputeOp0 error
            // .{ .pathname = "cairo_programs/field_arithmetic.json", .layout = "all_cairo" },
            // TODO: merge blake hint
            // .{ .pathname = "cairo_programs/finalize_blake2s.json", .layout = "all_cairo" },
            // TODO: merge blake hint
            // .{ .pathname = "cairo_programs/finalize_blake2s_v2_hint.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/find_element.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/fq.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp1 error
            // .{ .pathname = "cairo_programs/fq_test.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/function_return.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/function_return_if_print.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/function_return_to_variable.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/garaga.json", .layout = "all_cairo" },
            // TODO: FailedToComputeOp1 error
            // .{ .pathname = "cairo_programs/highest_bitlen.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/if_and_prime.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/if_in_function.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/if_list.json", .layout = "all_cairo" },
            // TODO: UnknownOp0 error
            // .{ .pathname = "cairo_programs/if_reloc_equal.json", .layout = "all_cairo" },

            // .{ .pathname = "cairo_programs/keccak_compiled.json", .layout = "all_cairo" },
            .{ .pathname = "cairo_programs/keccak_builtin.json", .layout = "all_cairo" },
            // .{ .pathname = "cairo_programs/keccak_integration_tests.json", .layout = "all_cairo" },
            // .{ .pathname = "cairo_programs/keccak_copy_inputs.json", .layout = "all_cairo" },
        };
        cairo_programs = temp_array[0..];
    }

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

        const result = cairo_run(allocator, test_cairo_program.pathname, test_cairo_program.layout, test_cairo_program.extensive_hints);

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

pub fn cairo_run(allocator: std.mem.Allocator, pathname: []const u8, layout: []const u8, extensive_hints: bool) !void {
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.realpath(pathname, &buffer);

    var parsed_program = try ProgramJson.parseFromFile(allocator, path);
    defer parsed_program.deinit();

    var entrypoint: []const u8 = "main";

    const instructions = try parsed_program.value.readData(allocator);

    const vm = try CairoVM.init(
        allocator,
        .{},
    );

    // when
    var runner = try CairoRunner.init(
        allocator,
        try parsed_program.value.parseProgramJson(allocator, &entrypoint, extensive_hints),
        layout,
        instructions,
        vm,
        false,
    );
    defer runner.deinit(allocator);

    const end = try runner.setupExecutionState(false);
    errdefer std.debug.print("failed on step: {}\n", .{runner.vm.current_step});

    // then
    var hint_processor: HintProcessor = .{};
    try runner.runUntilPC(end, extensive_hints, &hint_processor);
    try runner.endRun();
}
