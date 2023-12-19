const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const BuiltinRunner = @import("../builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const Config = @import("../config.zig").Config;
const CairoVM = @import("../core.zig").CairoVM;
const CairoLayout = @import("../types/layout.zig").CairoLayout;
const OutputBuiltinRunner = @import("../builtins/builtin_runner/output.zig").OutputBuiltinRunner;
const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const Program = @import("../types/program.zig").Program;
const CairoRunnerError = @import("../error.zig").CairoRunnerError;
const trace_context = @import("../trace_context.zig");
const RelocatedTraceEntry = trace_context.TraceContext.RelocatedTraceEntry;
const starknet_felt = @import("../../math/fields/starknet.zig");
const Felt252 = starknet_felt.Felt252;

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
    layout: CairoLayout,
    proof_mode: bool,
    run_ended: bool = false,
    relocated_trace: []RelocatedTraceEntry = undefined,

    pub fn init(
        allocator: Allocator,
        program: Program,
        layout: []const u8,
        instructions: std.ArrayList(MaybeRelocatable),
        vm: CairoVM,
        proof_mode: bool,
    ) !Self {
        var runner_layout: CairoLayout = undefined;
        const Case = enum { plain, small, dynamic, all_cairo };
        const case = std.meta.stringToEnum(Case, layout) orelse return CairoRunnerError.InvalidLayout;
        switch (case) {
            .plain => runner_layout = CairoLayout.plainInstance(),
            .small => runner_layout = CairoLayout.smallInstance(),
            .dynamic => runner_layout = CairoLayout.dynamicInstance(),
            .all_cairo => runner_layout = CairoLayout.allCairoInstance(allocator) catch |err| {
                return err;
            },
        }
        return .{
            .allocator = allocator,
            .program = program,
            .layout = runner_layout,
            .instructions = instructions,
            .vm = vm,
            .function_call_stack = std.ArrayList(MaybeRelocatable).init(allocator),
            .proof_mode = proof_mode,
        };
    }

    pub fn initBuiltins(self: *Self, vm: *CairoVM) !void {
        var builtinRunners = ArrayList(BuiltinRunner).init(self.allocator);
        if (self.layout.builtins.output) {
            try builtinRunners.append(BuiltinRunner{ .Output = OutputBuiltinRunner.initDefault(self.allocator)} );
        }
        vm.builtin_runners = builtinRunners;
    }

    pub fn setupExecutionState(self: *Self) !Relocatable {
        try self.initBuiltins(&self.vm);
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

        // TODO handle proof_mode case

        self.run_ended = true;
    }

    pub fn relocate(self: *Self) !void {
        _ = try self.vm.segments.computeEffectiveSize(false);

        const relocation_table = try self.vm.segments.relocateSegments(self.allocator);
        try self.vm.relocateTrace(relocation_table);
        // relocate_memory here
        self.relocated_trace = try self.vm.getRelocatedTrace();
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
