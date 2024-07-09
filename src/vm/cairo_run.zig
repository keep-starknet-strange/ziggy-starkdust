const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const security = @import("security.zig");
const CairoRunner = @import("runners/cairo_runner.zig").CairoRunner;
const CairoVM = @import("core.zig").CairoVM;
const Config = @import("config.zig").Config;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const Program = @import("types/program.zig").Program;
const ProgramJson = @import("types/programjson.zig").ProgramJson;
const HintProcessor = @import("../hint_processor/hint_processor_def.zig").CairoVMHintProcessor;
const ExecutionScopes = @import("types/execution_scopes.zig").ExecutionScopes;
const MaybeRelocatable = @import("./memory/relocatable.zig").MaybeRelocatable;

const trace_context = @import("./trace_context.zig");
const RelocatedTraceEntry = trace_context.RelocatedTraceEntry;
const RelocatedFelt252 = trace_context.RelocatedFelt252;

/// Writes the relocated/encoded trace to specified destination.
///
/// # Arguments
///
/// - `relocated_trace`:  The trace of register execution cycles, relocated.
/// - `dest`: The destination file that the trace is to be written.
pub fn writeEncodedTrace(relocated_trace: []const RelocatedTraceEntry, dest: anytype) !void {
    var buf: [8]u8 = undefined;
    for (relocated_trace) |entry| {
        std.mem.writeInt(u64, &buf, entry.ap, .little);
        _ = try dest.write(&buf);

        std.mem.writeInt(u64, &buf, entry.fp, .little);
        _ = try dest.write(&buf);

        std.mem.writeInt(u64, &buf, entry.pc, .little);
        _ = try dest.write(&buf);
    }
}

/// Writes the relocated/encoded memory to specified destination.
///
/// # Arguments
///
/// - `relocated_memory`:  The post-execution memory, relocated.
/// - `dest`: The destination file that the memory is to be written.
pub fn writeEncodedMemory(relocated_memory: []?Felt252, dest: anytype) !void {
    var buf: [8]u8 = undefined;

    for (relocated_memory, 0..) |memory_cell, i| {
        if (memory_cell) |cell| {
            std.mem.writeInt(u64, &buf, i, .little);
            _ = try dest.write(&buf);
            _ = try dest.write(&cell.toBytesLe());
        }
    }
}

pub const CairoRunConfig = struct {
    entrypoint: []const u8 = "main",
    trace_enabled: bool = false,
    relocate_mem: bool = false,
    layout: []const u8 = "plain",
    proof_mode: bool = false,
    secure_run: ?bool = null,
    disable_trace_padding: bool = false,
    allow_missing_builtins: ?bool = null,
};

// cairoRun - running cairo program, after call u own runner.vm, own runner and own runner.vm.segments.memory
// so after call u need deallocate runner.vm, calll runner.vm.segments.memory.deinitData and runner.deinit
pub fn cairoRun(
    allocator: std.mem.Allocator,
    program_content: []const u8,
    cairo_run_config: CairoRunConfig,
    hint_processor: *HintProcessor,
) !CairoRunner {
    var parsed_program = try ProgramJson.parseFromString(allocator, program_content);
    defer parsed_program.deinit();

    var program = try parsed_program.value.parseProgramJson(allocator, @constCast(&cairo_run_config.entrypoint));

    const instructions = parsed_program.value.readData(allocator) catch |err| {
        program.deinit(allocator);
        return err;
    };

    return cairoRunProgram(allocator, program, cairo_run_config, hint_processor, instructions);
}

pub fn cairoRunProgram(
    allocator: std.mem.Allocator,
    program: Program,
    cairo_run_config: CairoRunConfig,
    hint_processor: *HintProcessor,
    instructions: std.ArrayList(MaybeRelocatable),
) !CairoRunner {
    const execution_scopes = ExecutionScopes.init(allocator) catch |err| {
        // hack to deallocate program (TODO: think how to do it better)
        var p = program;
        p.deinit(allocator);
        instructions.deinit();
        return err;
    };

    return cairoRunProgramWithInitialScope(allocator, program, cairo_run_config, hint_processor, instructions, execution_scopes);
}

/// Runs a program with a customized execution scope.
/// put exec_scopes as argument, func take controll on it deallocation due error, due success CairoRunner will control deallocate
/// also as passed program, CairoRunner take control on program on error/success run
pub fn cairoRunProgramWithInitialScope(
    allocator: std.mem.Allocator,
    program: Program,
    cairo_run_config: CairoRunConfig,
    hint_processor: *HintProcessor,
    instructions: std.ArrayList(MaybeRelocatable),
    exec_scopes: ExecutionScopes,
) !CairoRunner {
    const secure_run = cairo_run_config.secure_run orelse !cairo_run_config.proof_mode;

    const allow_missing_builtins = cairo_run_config.allow_missing_builtins orelse cairo_run_config.proof_mode;

    var runner = val: {
        errdefer instructions.deinit();
        errdefer exec_scopes.deinit();
        errdefer {
            // hack to deallocate
            var p = program;
            p.deinit(allocator);
        }

        var vm = try allocator.create(CairoVM);
        errdefer allocator.destroy(vm);

        vm.* = try CairoVM.initV2(allocator, cairo_run_config.trace_enabled);
        errdefer vm.deinit();

        break :val try CairoRunner.initV2(
            allocator,
            program,
            cairo_run_config.layout,
            instructions,
            vm,
            cairo_run_config.proof_mode,
            exec_scopes,
        );
    };
    errdefer runner.deinit(allocator);

    const end = try runner.setupExecutionState(allow_missing_builtins);

    try runner.runUntilPC(end, hint_processor);

    if (cairo_run_config.proof_mode) try runner.runForSteps(1, hint_processor);

    try runner.endRun(
        allocator,
        cairo_run_config.disable_trace_padding,
        false,
        hint_processor,
    );

    try runner.vm.verifyAutoDeductions(allocator);
    try runner.readReturnValue(allow_missing_builtins);

    //     cairo_runner.read_return_values(allow_missing_builtins)?;
    if (cairo_run_config.proof_mode) try runner.finalizeSegments();

    if (secure_run) try security.verifySecureRunner(allocator, &runner, true, null);

    try runner.relocate(cairo_run_config.relocate_mem);

    return runner;
}

/// Instruments the `CairoRunner` to initialize an execution of a cairo program based on Config params.
///
/// # Arguments
///
/// - `allocator`:  The allocator to initialize the CairoRunner and parsing of the program json.
/// - `config`: The config struct that defines the params that the CairoRunner uses to instantiate the vm state for running.
pub fn runConfig(allocator: Allocator, config: Config) !CairoRunner {
    const secure_run = config.secure_run orelse !config.proof_mode;

    var vm = try CairoVM.init(
        allocator,
        config,
    );

    var parsed_program = try ProgramJson.parseFromFile(allocator, config.filename);
    const instructions = try parsed_program.value.readData(allocator);
    defer parsed_program.deinit();

    var entrypoint: []const u8 = "main";

    // TODO: add flag for extensive_hints
    var runner = try CairoRunner.init(
        allocator,
        try parsed_program.value.parseProgramJson(allocator, &entrypoint),
        config.layout,
        instructions,
        &vm,
        config.proof_mode,
    );
    errdefer runner.deinit(allocator);

    const end = try runner.setupExecutionState(config.allow_missing_builtins orelse config.proof_mode);

    // TODO: make flag for extensive_hints
    var hint_processor: HintProcessor = .{};
    try runner.runUntilPC(end, &hint_processor);

    if (config.proof_mode) try runner.runForSteps(1, &hint_processor);

    try runner.endRun(
        allocator,
        false,
        false,
        &hint_processor,
    );

    try runner.vm.verifyAutoDeductions(allocator);

    // cairo_runner.read_return_values(allow_missing_builtins)?;

    if (config.proof_mode)
        try runner.finalizeSegments();

    if (secure_run)
        try security.verifySecureRunner(allocator, &runner, true, null);

    if (config.output_trace != null or config.output_memory != null) {
        try runner.relocate();

        var writer: std.io.BufferedWriter(5 * 1024 * 1024, std.fs.File.Writer) = .{ .unbuffered_writer = undefined };

        if (config.output_trace) |trace_path| {
            const trace_file = try std.fs.cwd().createFile(trace_path, .{});
            defer trace_file.close();

            writer.unbuffered_writer = trace_file.writer();

            try writeEncodedTrace(runner.relocated_trace.?, &writer);

            try writer.flush();
        }

        if (config.output_memory) |mem_path| {
            const mem_file = try std.fs.cwd().createFile(mem_path, .{});
            defer mem_file.close();

            writer.unbuffered_writer = mem_file.writer();

            try writeEncodedMemory(runner.relocated_memory.items, &writer);
            try writer.flush();
        }
    }

    return runner;
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

const tmpDir = std.testing.tmpDir;

test "EncodedMemory: can round trip from valid memory binary" {
    // Given
    const allocator = std.testing.allocator;
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    // where  `cairo_memory_struct` is sourced (graciously) from
    // https://github.com/lambdaclass/cairo-vm/blob/main/cairo_programs/trace_memory/cairo_trace_struct#L1
    const path = try std.posix.realpath("cairo_programs/trace_memory/cairo_memory_struct", &buffer);

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var reader = file.reader();
    var relocated_memory = std.ArrayList(?Felt252).init(allocator);
    defer relocated_memory.deinit();

    // Relocated addresses start at 1,
    // it's the law.
    try relocated_memory.append(null);

    // Read the entire file into a bytes buffer
    var expected_file_bytes = std.ArrayList(u8).init(allocator);
    defer expected_file_bytes.deinit();
    try expected_file_bytes.resize((try file.stat()).size);

    _ = try reader.readAll(expected_file_bytes.items);

    // where logic in how to go from memory binary back to relocated memory
    // is
    // a row is a index eight bytes x value thirty-two bytes
    const row_size = 8 + 32;
    var i: usize = 0;
    while (i < expected_file_bytes.items.len) : (i += row_size) {
        var idx_buff: [8]u8 = undefined;
        std.mem.copyForwards(u8, &idx_buff, expected_file_bytes.items[i .. i + 8]);
        const idx = std.mem.readInt(u64, &idx_buff, .little);

        var value_buf: [32]u8 = undefined;
        std.mem.copyForwards(u8, &value_buf, expected_file_bytes.items[i + 8 .. i + row_size]);

        const value = std.mem.readInt(u256, &value_buf, .little);

        try relocated_memory.insert(idx, Felt252.fromInt(u256, value));
    }

    // now we have the shape of a bonafide relocated memory,
    // we write it to a temp file
    // Create a temporary file
    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const tmp_file_name = "temp_encoded_memory";
    const tmp_file = try tmp.dir.createFile(tmp_file_name, .{});

    defer tmp_file.close();

    var writer = tmp_file.writer();
    try writeEncodedMemory(relocated_memory.items, &writer);

    // Read back the contents of the file
    const read_file = try tmp.dir.openFile(tmp_file_name, .{});
    defer read_file.close();

    var file_reader = read_file.reader();
    var actual_bytes = std.ArrayList(u8).init(allocator);
    defer actual_bytes.deinit();
    try actual_bytes.resize((try tmp_file.stat()).size);

    _ = try file_reader.readAll(actual_bytes.items);

    try std.testing.expectEqualSlices(u8, expected_file_bytes.items, actual_bytes.items);
    try tmp.dir.deleteFile(tmp_file_name);
}
