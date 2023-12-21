const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const BuiltinRunner = @import("../builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const Config = @import("../config.zig").Config;
const CairoVM = @import("../core.zig").CairoVM;
const CairoLayout = @import("../types/layout.zig").CairoLayout;
const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const ProgramJson = @import("../types/programjson.zig").ProgramJson;
const CairoRunnerError = @import("../error.zig").CairoRunnerError;
const RunnerError = @import("../error.zig").RunnerError;
const trace_context = @import("../trace_context.zig");
const RelocatedTraceEntry = trace_context.TraceContext.RelocatedTraceEntry;
const starknet_felt = @import("../../math/fields/starknet.zig");
const Felt252 = starknet_felt.Felt252;

pub const CairoRunner = struct {
    const Self = @This();

    program: ProgramJson,
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
        program: ProgramJson,
        layout: []const u8,
        instructions: std.ArrayList(MaybeRelocatable),
        vm: CairoVM,
        proof_mode: bool,
    ) !Self {
        const Case = enum { plain, small, dynamic, all_cairo };
        return .{
            .allocator = allocator,
            .program = program,
            .layout = switch (std.meta.stringToEnum(Case, layout) orelse return CairoRunnerError.InvalidLayout) {
                .plain => CairoLayout.plainInstance(),
                .small => CairoLayout.smallInstance(),
                .dynamic => CairoLayout.dynamicInstance(),
                .all_cairo => try CairoLayout.allCairoInstance(allocator),
            },
            .instructions = instructions,
            .vm = vm,
            .function_call_stack = std.ArrayList(MaybeRelocatable).init(allocator),
            .proof_mode = proof_mode,
        };
    }

    pub fn initBuiltins(self: *Self, vm: *CairoVM) !void {
        vm.builtin_runners = try CairoLayout.setUpBuiltinRunners(
            self.layout,
            self.allocator,
            self.proof_mode,
            self.program.builtins,
        );
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
        // stores the bytecode of the executed Cairo ProgramJson
        self.program_base = try self.vm.segments.addSegment();
        // stores the execution stack
        self.execution_base = try self.vm.segments.addSegment();

        for (self.vm.builtin_runners.items) |*builtin_runner| {
            try builtin_runner.initSegments(self.vm.segments);
        }
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
        for (self.vm.builtin_runners.items) |*builtin_runner| {
            const builtin_stack = try builtin_runner.initialStack(self.allocator);
            defer builtin_stack.deinit();
            for (builtin_stack.items) |item| {
                try self.function_call_stack.append(item);
            }
        }
        // TODO handle the case where we are running in proof mode
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

        // TODO handle proof_mode case
        self.run_ended = true;
    }

    pub fn relocate(self: *Self) !void {
        // Presuming the default case of `allow_tmp_segments` in python version
        _ = try self.vm.segments.computeEffectiveSize(false);

        const relocation_table = try self.vm.segments.relocateSegments(self.allocator);
        try self.vm.relocateTrace(relocation_table);
        // relocate_memory here
        self.relocated_trace = try self.vm.getRelocatedTrace();
    }

    pub fn deinit(self: *Self) void {
        // currently handling the deinit of the json.Parsed(ProgramJson) outside of constructor
        // otherwise the runner would always assume json in its interface
        // self.program.deinit();
        self.function_call_stack.deinit();
        self.instructions.deinit();
        self.vm.segments.memory.deinitData(self.allocator);
        self.layout.deinit();
        self.vm.deinit();
    }
};
