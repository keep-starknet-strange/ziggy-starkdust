const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const CairoRunner = @import("./runners/cairo_runner.zig").CairoRunner;
const CairoVM = @import("./core.zig").CairoVM;
const Config = @import("./config.zig").Config;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const Program = @import("./types/program.zig").Program;
const ProgramJson = @import("./types/programjson.zig").ProgramJson;

const trace_context = @import("./trace_context.zig");
const RelocatedTraceEntry = trace_context.TraceContext.RelocatedTraceEntry;

/// Writes the relocated/encoded trace to specified destination.
///
/// # Arguments
///
/// - `relocated_trace`:  The trace of register execution cycles, relocated.
/// - `dest`: The destination file that the trace is to be written.
pub fn writeEncodedTrace(relocated_trace: []const RelocatedTraceEntry, dest: *std.fs.File.Writer) !void {
    for (relocated_trace) |entry| {
        try dest.writeInt(u64, try entry.ap.tryIntoU64(), .little);
        try dest.writeInt(u64, try entry.fp.tryIntoU64(), .little);
        try dest.writeInt(u64, try entry.pc.tryIntoU64(), .little);
    }
}

/// Writes the relocated/encoded memory to specified destination.
///
/// # Arguments
///
/// - `relocated_memory`:  The post-execution memory, relocated.
/// - `dest`: The destination file that the memory is to be written.
pub fn writeEncodedMemory(relocated_memory: []?Felt252, dest: *std.fs.File.Writer) !void {
    for (relocated_memory, 0..) |memory_cell, i| {
        if (memory_cell == null) continue;
        try dest.writeInt(u64, i, .little);
        try dest.writeInt(u256, memory_cell.?.toInteger(), .little);
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

    const parsed_program = try ProgramJson.parseFromFile(allocator, config.filename);
    const instructions = try parsed_program.value.readData(allocator);
    defer parsed_program.deinit();

    var runner = try CairoRunner.init(allocator, parsed_program.value, config.layout, instructions, vm, config.proof_mode);
    defer runner.deinit();
    const end = try runner.setupExecutionState();
    try runner.runUntilPC(end);
    try runner.endRun();
    // TODO readReturnValues necessary for builtins

    if (config.output_trace) |trace_path| {
        try runner.relocate();

        const trace_file = try std.fs.cwd().createFile(trace_path, .{});
        defer trace_file.close();

        var trace_writer = trace_file.writer();
        try writeEncodedTrace(runner.relocated_trace, &trace_writer);
    }

    // blocked until memory relocation is implemented
    // if (config.output_memory) |mem_path| {
    //     const mem_file = try std.fs.cwd().createFile(mem_path, .{});
    //     defer mem_file.close();

    //     var mem_writer = mem_file.writer();
    //     try writeEncodedMemory(runner.relocated_trace, &mem_writer);
    // }
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

const tmpDir = std.testing.tmpDir;

test "EncodedMemory: can round trip from valid memory binary" {
    // Given
    const allocator = std.testing.allocator;
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    // where  `cairo_memory_struct` is sourced (graciously) from
    // https://github.com/lambdaclass/cairo-vm/blob/main/cairo_programs/trace_memory/cairo_trace_struct#L1
    const path = try std.os.realpath("cairo_programs/trace_memory/cairo_memory_struct", &buffer);

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

        try relocated_memory.insert(idx, Felt252.fromInteger(value));
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
