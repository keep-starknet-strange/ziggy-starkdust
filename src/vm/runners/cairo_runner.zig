const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const Config = @import("../config.zig").Config;
const CairoVM = @import("../core.zig").CairoVM;
const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const Program = @import("../types/program.zig").Program;
const CairoRunnerError = @import("../error.zig").CairoRunnerError;
const trace_context = @import("../trace_context.zig");
const RelocatedTraceEntry = trace_context.TraceContext.RelocatedTraceEntry;
const starknet_felt = @import("../../math/fields/starknet.zig");
const Felt252 = starknet_felt.Felt252;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

pub const CairoRunner = struct {
    const Self = @This();

    program: Program,
    allocator: Allocator,
    vm: CairoVM,
    program_base: Relocatable = undefined,
    execution_base: Relocatable = undefined,
    initial_pc: Relocatable = undefined,
    initial_ap: Relocatable = undefined,
    initial_fp: Relocatable = undefined,
    final_pc: *Relocatable = undefined,
    instructions: std.ArrayList(MaybeRelocatable),
    function_call_stack: std.ArrayList(MaybeRelocatable),
    entrypoint_name: []const u8 = "main",
    proof_mode: bool,
    run_ended: bool = false,
    relocated_trace: [] RelocatedTraceEntry = undefined,

    pub fn init(
        allocator: Allocator,
        program: Program,
        instructions: std.ArrayList(MaybeRelocatable),
        vm: CairoVM,
        proof_mode: bool,
    ) !Self {
        return .{
            .allocator = allocator,
            .program = program,
            .instructions = instructions,
            .vm = vm,
            .function_call_stack = std.ArrayList(MaybeRelocatable).init(allocator),
            .proof_mode = proof_mode,
        };
    }

    pub fn initBuiltins(self: *Self, vm: *CairoVM) !void {
        _ = self;
        _ = vm;
    }

    pub fn setupExecutionState(self: *Self) !Relocatable {
        try self.initSegments();
        const end = try self.initMainEntrypoint();
        self.initVM();
        return end;
    }

    /// Initializes common segments for the execution of a cairo program.
    pub fn initSegments(self: *Self) !void {

        // Common segments, as defined in pg 41 of the cairo paper
        // stores the bytecode of the executed Cairo Program
        self.program_base = try self.vm.segments.addSegment();
        // stores the execution stack
        self.execution_base = try self.vm.segments.addSegment();

        // TODO, add builtin segments when fib milestone is completed
    }

    /// Initializes runner state for execution, as in:
    /// Sets the proper initial program counter.
    /// Loads instructions to the initialized program segment.
    /// Loads the function call stack to the execution segment.
    /// # Arguments
    /// - `entrypoint:` The address, relative to the program segment, where execution begins.
    pub fn initState(self: *Self, entrypoint: usize) !void {
        self.initial_pc = self.program_base;
        self.initial_pc.addUintInPlace(entrypoint);

        _ = try self.vm.segments.loadData(
            self.allocator,
            self.program_base,
            &self.instructions,
        );

        _ = try self.vm.segments.loadData(
            self.allocator,
            self.execution_base,
            &self.function_call_stack,
        );
    }

    pub fn initFunctionEntrypoint(self: *Self, entrypoint: usize, return_fp: Relocatable) !Relocatable {
        var end = try self.vm.segments.addSegment();

        // per 6.1 of cairo whitepaper
        // a call stack usually increases a frame when a function is called
        // and decreases when a function returns,
        // but to situate the functionality with Cairo's read-only memory,
        // the frame pointer register is used to point to the current frame in the stack
        // the runner sets the return fp and establishes the end address that execution treats as the endpoint.
        try self.function_call_stack.append(MaybeRelocatable.fromRelocatable(return_fp));
        try self.function_call_stack.append(MaybeRelocatable.fromRelocatable(end));

        self.initial_fp = self.execution_base;
        self.initial_fp.addUintInPlace(@as(u64, self.function_call_stack.items.len));
        self.initial_ap = self.initial_fp;

        self.final_pc = &end;
        try self.initState(entrypoint);
        return end;
    }

    /// Initializes runner state for execution of a program from the `main()` entrypoint.
    pub fn initMainEntrypoint(self: *Self) !Relocatable {
        // TODO handle the necessary stack initializing for builtins
        // and the case where we are running in proof mode
        const return_fp = try self.vm.segments.addSegment();
        // Buffer for concatenation
        var buffer: [100]u8 = undefined;

        // Concatenate strings
        const full_entrypoint_name = try std.fmt.bufPrint(&buffer, "__main__.{s}", .{self.entrypoint_name});

        const main_offset: usize = self.program.identifiers.map.get(full_entrypoint_name).?.pc orelse 0;
        const end = try self.initFunctionEntrypoint(main_offset, return_fp);
        return end;
    }

    pub fn initVM(self: *Self) void {
        self.vm.run_context.ap.* = self.initial_ap;
        self.vm.run_context.fp.* = self.initial_fp;
        self.vm.run_context.pc.* = self.initial_pc;
    }

    pub fn runUntilPC(self: *Self, end: Relocatable) !void {
        while (!end.eq(self.vm.run_context.pc.*)) {
            try self.vm.step(self.allocator);
        }
    }

    pub fn endRun(self: *Self) !void {
        // TODO relocate memory
        // TODO call end_run in vm for builtins
        if (self.run_ended) {
            return CairoRunnerError.EndRunAlreadyCalled;
        }

        // Presuming the default case of `allow_tmp_segments` in python version
        _ = try self.vm.segments.computeEffectiveSize(false);

        // TODO handle proof_mode case

        self.run_ended = true;
    }

    /// Ensures that the trace is relocated and is retrievable from the VM and returns it.
    pub fn consolidateTrace(self: *Self) ![]RelocatedTraceEntry {
        const relocation_table = try self.vm.segments.relocateSegments(self.allocator);
        try self.vm.relocateTrace(relocation_table);

        const relocated_trace = self.vm.getRelocatedTrace();
        return relocated_trace;
    }

    pub fn deinit(self: *Self) void {
        // currently handling the deinit of the json.Parsed(Program) outside of constructor
        // otherwise the runner would always assume json in its interface
        // self.program.deinit();
        self.function_call_stack.deinit();
        self.instructions.deinit();
        self.vm.segments.memory.deinitData(self.allocator);
        self.vm.deinit();
    }
};

pub fn writeEncodedTrace(relocated_trace: []const RelocatedTraceEntry, dest: *std.fs.File.Writer) !void {
    std.debug.print("LENGTH OF TRACE: {any}\n", .{relocated_trace.len});    
    for (relocated_trace) |entry| {
        const ap = try entry.ap.tryIntoU64();
        const fp = try entry.fp.tryIntoU64();
        const pc = try entry.pc.tryIntoU64();
        _ = try dest.writeInt(u64, ap, .little);
        _ = try dest.writeInt(u64, fp, .little);
        _ = try dest.writeInt(u64, pc, .little);
    }
}

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