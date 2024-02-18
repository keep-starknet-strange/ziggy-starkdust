const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const HintData = @import("../../hint_processor/hint_processor_def.zig").HintData;
const HashMapWithArray = @import("../../hint_processor/hint_utils.zig").HashMapWithArray;
const HintProcessor = @import("../../hint_processor/hint_processor_def.zig").CairoVMHintProcessor;
const BuiltinRunner = @import("../builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const Config = @import("../config.zig").Config;
const CairoVM = @import("../core.zig").CairoVM;
const CairoLayout = @import("../types/layout.zig").CairoLayout;
const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const ProgramJson = @import("../types/programjson.zig").ProgramJson;
const Program = @import("../types/program.zig").Program;
const CairoRunnerError = @import("../error.zig").CairoRunnerError;
const RunnerError = @import("../error.zig").RunnerError;
const MemoryError = @import("../error.zig").MemoryError;
const trace_context = @import("../trace_context.zig");
const RelocatedTraceEntry = trace_context.TraceContext.RelocatedTraceEntry;
const starknet_felt = @import("../../math/fields/starknet.zig");
const Felt252 = starknet_felt.Felt252;
const OutputBuiltinRunner = @import("../builtins/builtin_runner/output.zig").OutputBuiltinRunner;
const BitwiseBuiltinRunner = @import("../builtins/builtin_runner/bitwise.zig").BitwiseBuiltinRunner;
const ExecutionScopes = @import("../types/execution_scopes.zig").ExecutionScopes;
const RangeCheckBuiltinRunner = @import("../builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Tracks the step resources of a cairo execution run.
const RunResources = struct {
    const Self = @This();
    // We consider the 'default' mode of RunResources having infinite steps.
    n_steps: ?usize = null,

    pub fn init(n_steps: usize) Self {
        return .{ .n_steps = n_steps };
    }

    pub fn consumed(self: *Self) bool {
        if (self.n_steps) |n_steps| {
            return n_steps == 0;
        }

        return false;
    }

    pub fn consumeStep(self: *Self) void {
        if (self.n_steps) |n_steps| {
            if (n_steps > 0) {
                self.n_steps = n_steps - 1;
            }
        }
    }
};

/// This interface is used in conditions where vm execution needs to be constrained by a certain amount of steps.
/// It is primarily used in the context of Starknet and implemented by HintProcessors.
const ResourceTracker = struct {
    const Self = @This();

    // define interface fields: ptr,vtab
    ptr: *anyopaque, //ptr to instance
    vtab: *const VTab, //ptr to vtab
    const VTab = struct {
        consumed: *const fn (ptr: *anyopaque) bool,
        consumeStep: *const fn (ptr: *anyopaque) void,
    };

    /// Returns true if there are no resource-steps available.
    pub fn consumed(self: Self) bool {
        return self.vtab.consumed(self.ptr);
    }

    /// Subtracts a single step from what is initialized as available.
    pub fn consumeStep(self: Self) void {
        self.vtab.consumeStep(self.ptr);
    }

    // cast concrete implementation types/objs to interface
    pub fn init(obj: anytype) Self {
        const Ptr = @TypeOf(obj);
        const PtrInfo = @typeInfo(Ptr);
        std.debug.assert(PtrInfo == .Pointer); // Must be a pointer
        std.debug.assert(PtrInfo.Pointer.size == .One); // Must be a single-item pointer
        std.debug.assert(@typeInfo(PtrInfo.Pointer.child) == .Struct); // Must point to a struct
        const impl = struct {
            fn consumed(ptr: *anyopaque) bool {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return self.consumed();
            }
            fn consumeStep(ptr: *anyopaque) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                self.consumeStep();
            }
        };
        return .{
            .ptr = obj,
            .vtab = &.{
                .consumed = impl.consumed,
                .consumeStep = impl.consumeStep,
            },
        };
    }
};

pub const RunnerMode = enum { execution_mode, proof_mode_canonical, proof_mode_cairo1 };

const BuiltinInfo = struct { segment_index: usize, stop_pointer: usize };

pub const CairoRunner = struct {
    const Self = @This();

    program: ProgramJson,
    allocator: Allocator,
    vm: CairoVM,
    program_base: Relocatable = undefined,
    execution_base: Relocatable = undefined,
    initial_pc: ?Relocatable = null,
    initial_ap: ?Relocatable = null,
    initial_fp: ?Relocatable = null,
    final_pc: *Relocatable = undefined,
    instructions: std.ArrayList(MaybeRelocatable),
    // function_call_stack: std.ArrayList(MaybeRelocatable),
    entrypoint_name: []const u8 = "main",
    layout: CairoLayout,
    runner_mode: RunnerMode,
    run_ended: bool = false,
    execution_public_memory: ?std.ArrayList(usize) = null,
    relocated_trace: []RelocatedTraceEntry = undefined,
    relocated_memory: ArrayList(?Felt252),
    execution_scopes: ExecutionScopes = undefined,

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
            .layout = switch (std.meta.stringToEnum(Case, layout) orelse
                return CairoRunnerError.InvalidLayout) {
                .plain => CairoLayout.plainInstance(),
                .small => CairoLayout.smallInstance(),
                .dynamic => CairoLayout.dynamicInstance(),
                .all_cairo => try CairoLayout.allCairoInstance(allocator),
            },
            .instructions = instructions,
            .vm = vm,
            .runner_mode = if (proof_mode) .proof_mode_canonical else .execution_mode,
            .relocated_memory = ArrayList(?Felt252).init(allocator),
        };
    }

    pub fn isProofMode(self: *Self) bool {
        return self.runner_mode == .proof_mode_canonical or self.runner_mode == .proof_mode_cairo1;
    }

    pub fn initBuiltins(self: *Self, vm: *CairoVM) !void {
        vm.builtin_runners = try CairoLayout.setUpBuiltinRunners(
            self.layout,
            self.allocator,
            self.isProofMode(),
            self.program.builtins.?,
        );
    }

    pub fn setupExecutionState(self: *Self) !Relocatable {
        try self.initBuiltins(&self.vm);
        try self.initSegments(null);
        const end = try self.initMainEntrypoint();
        try self.initVM();
        return end;
    }

    /// Initializes common segments for the execution of a cairo program.
    ///
    /// This function initializes the memory segments required for the execution of a Cairo program.
    /// It creates segments for the program base, execution stack, and built-in runners.
    ///
    /// # Arguments
    ///
    /// - `program_base`: An optional `Relocatable` representing the base address for the program.
    ///
    /// # Returns
    ///
    /// This function returns `void`.
    pub fn initSegments(self: *Self, program_base: ?Relocatable) !void {
        // Set the program base to the provided value or create a new segment.
        self.program_base = if (program_base) |base| base else try self.vm.segments.addSegment();

        // Create a segment for the execution stack.
        self.execution_base = try self.vm.segments.addSegment();

        // Initialize segments for each built-in runner.
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
    pub fn initState(self: *Self, entrypoint: usize, stack: *std.ArrayList(MaybeRelocatable)) !void {
        self.initial_pc = self.program_base;
        self.initial_pc.?.addUintInPlace(entrypoint);

        _ = try self.vm.segments.loadData(
            self.allocator,
            self.program_base,
            &self.instructions,
        );

        _ = try self.vm.segments.loadData(
            self.allocator,
            self.execution_base,
            stack,
        );
    }

    pub fn initFunctionEntrypoint(self: *Self, entrypoint: usize, return_fp: Relocatable, stack: *std.ArrayList(MaybeRelocatable)) !Relocatable {
        var end = try self.vm.segments.addSegment();

        // per 6.1 of cairo whitepaper
        // a call stack usually increases a frame when a function is called
        // and decreases when a function returns,
        // but to situate the functionality with Cairo's read-only memory,
        // the frame pointer register is used to point to the current frame in the stack
        // the runner sets the return fp and establishes the end address that execution treats as the endpoint.
        try stack.append(MaybeRelocatable.fromRelocatable(return_fp));
        try stack.append(MaybeRelocatable.fromRelocatable(end));

        self.initial_fp = self.execution_base;
        self.initial_fp.?.addUintInPlace(@as(u64, stack.items.len));
        self.initial_ap = self.initial_fp;

        self.final_pc = &end;
        try self.initState(entrypoint, stack);
        return end;
    }

    /// Initializes runner state for execution of a program from the `main()` entrypoint.
    pub fn initMainEntrypoint(self: *Self) !Relocatable {
        var stack = std.ArrayList(MaybeRelocatable).init(self.allocator);
        defer stack.deinit();

        for (self.vm.builtin_runners.items) |*builtin_runner| {
            const builtin_stack = try builtin_runner.initialStack(self.allocator);
            defer builtin_stack.deinit();
            for (builtin_stack.items) |item| {
                try stack.append(item);
            }
        }

        if (self.isProofMode()) {
            var target_offset: usize = 2;

            if (self.runner_mode == .proof_mode_canonical) {
                var stack_prefix = try std.ArrayList(MaybeRelocatable).initCapacity(self.allocator, 2 + stack.items.len);
                defer stack_prefix.deinit();

                try stack_prefix.append(MaybeRelocatable.fromRelocatable(try self.execution_base.addUint(target_offset)));
                try stack_prefix.appendSlice(stack.items);

                var execution_public_memory = try std.ArrayList(usize).initCapacity(self.allocator, stack_prefix.items.len);
                for (0..stack_prefix.items.len) |v| {
                    try execution_public_memory.append(v);
                }
                self.execution_public_memory = execution_public_memory;

                try self.initState(try (self.program.getStartPc() orelse RunnerError.NoProgramStart), &stack_prefix);
            } else {
                target_offset = stack.items.len + 2;

                const return_fp = try self.vm.segments.addSegment();
                const end = try self.vm.segments.addSegment();
                try stack.append(MaybeRelocatable.fromRelocatable(return_fp));
                try stack.append(MaybeRelocatable.fromRelocatable(end));

                try self.initState(try (self.program.getStartPc() orelse RunnerError.NoProgramStart), &stack);
            }

            self.initial_fp = try self.execution_base.addUint(target_offset);
            self.initial_ap = self.initial_fp;

            return self.program_base.addUint(try (self.program.getEndPc() orelse RunnerError.NoProgramEnd));
        }

        const return_fp = try self.vm.segments.addSegment();
        // Buffer for concatenation
        var buffer: [100]u8 = undefined;

        // Concatenate strings
        const full_entrypoint_name = try std.fmt.bufPrint(&buffer, "__main__.{s}", .{self.entrypoint_name});

        if (self.program.identifiers) |identifiers| {
            if (identifiers.map.get(full_entrypoint_name)) |identifier| {
                if (identifier.pc) |pc| {
                    return self.initFunctionEntrypoint(pc, return_fp, &stack);
                }
            }
        }

        return RunnerError.MissingMain;
    }

    /// Initializes the runner's virtual machine (VM) state for execution.
    ///
    /// This function sets up the initial state of the VM, including the program counter (PC),
    /// activation pointer (AP), and frame pointer (FP). It also adds validation rules for built-in runners
    /// and validates the existing memory segments.
    ///
    /// # Arguments
    ///
    /// - `self`: A mutable reference to the `CairoRunner` instance.
    ///
    /// # Returns
    ///
    /// This function returns `void`. In case of errors, it returns a `RunnerError`.
    pub fn initVM(self: *Self) !void {
        // Set VM state: AP, FP, PC
        self.vm.run_context.ap.* = self.initial_ap orelse return RunnerError.NoAP;
        self.vm.run_context.fp.* = self.initial_fp orelse return RunnerError.NoFP;
        self.vm.run_context.pc.* = self.initial_pc orelse return RunnerError.NoPC;

        // Add validation rules for built-in runners
        for (self.vm.builtin_runners.items) |*builtin_runner| {
            try builtin_runner.addValidationRule(self.vm.segments.memory);
        }

        // Validate existing memory segments
        self.vm.segments.memory.validateExistingMemory() catch return RunnerError.MemoryValidationError;
    }

    pub fn getHintDataMap(self: *Self, hint_processor: HintProcessor, program: *Program) !HashMapWithArray(usize, HintData) {
        const result = HashMapWithArray(usize, HintData).init(self.allocator);
        errdefer result.deinit();

        while (program.hints.iterator().next()) |item| {
            const pc = item.key_ptr.*;
            const hints_params = item.value_ptr.*;
            const hint_datas = try std.ArrayList(HintData).initCapacity(self.allocator, hints_params.items.len);
            errdefer hint_datas.deinit();

            for (hints_params.items) |hint_param| {
                try hint_datas.append(
                    try hint_processor.compileHint(self.allocator, hint_param, program.shared_program_data.reference_manager.items),
                );
            }

            try result.put(pc, hint_datas);
        }

        return result;
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

    /// Relocates the memory segments based on the provided relocation table.
    /// This function iterates through each memory cell in the VM segments,
    /// relocates the addresses, and updates the `relocated_memory` array.
    ///
    /// # Arguments
    /// - `relocation_table`: A table containing relocation information for memory cells.
    ///                       Each entry specifies the new address after relocation.
    ///
    /// # Returns
    /// - `MemoryError.Relocation`: If the `relocated_memory` array is not empty,
    ///                             indicating that relocation has already been performed.
    ///                             Or, if any errors occur during relocation.
    pub fn relocateMemory(self: *Self, relocation_table: []usize) !void {
        // Check if relocation has already been performed.
        // If `relocated_memory` is not empty, return `MemoryError.Relocation`.
        if (!(self.relocated_memory.items.len == 0)) return MemoryError.Relocation;

        // Initialize the first entry in `relocated_memory` with `null`.
        try self.relocated_memory.append(null);

        // Iterate through each memory segment in the VM.
        for (self.vm.segments.memory.data.items, 0..) |segment, index| {
            // Iterate through each memory cell in the segment.
            for (segment.items, 0..) |memory_cell, segment_offset| {
                // If the memory cell is not null (contains data).
                if (memory_cell) |cell| {
                    // Create a new `Relocatable` representing the relocated address.
                    const relocated_address = try Relocatable.init(
                        @intCast(index),
                        segment_offset,
                    ).relocateAddress(relocation_table);

                    // Resize `relocated_memory` if needed.
                    if (self.relocated_memory.items.len <= relocated_address) {
                        try self.relocated_memory.resize(relocated_address + 1);
                    }

                    // Update the entry in `relocated_memory` with the relocated value of the memory cell.
                    self.relocated_memory.items[relocated_address] = try cell.maybe_relocatable.relocateValue(relocation_table);
                } else {
                    // If the memory cell is null, append `null` to `relocated_memory`.
                    try self.relocated_memory.append(null);
                }
            }
        }
    }

    pub fn relocate(self: *Self) !void {
        // Presuming the default case of `allow_tmp_segments` in python version
        _ = try self.vm.segments.computeEffectiveSize(false);

        const relocation_table = try self.vm.segments.relocateSegments(self.allocator);
        try self.vm.relocateTrace(relocation_table);
        try self.relocateMemory(relocation_table);
        self.relocated_trace = try self.vm.getRelocatedTrace();
    }

    /// Retrieves information about the builtin segments.
    ///
    /// This function iterates through the builtin runners of the CairoRunner and gathers
    /// information about the memory segments, including their indices and stop pointers.
    /// The gathered information is stored in an ArrayList of BuiltinInfo structures.
    ///
    /// # Arguments
    /// - `self`: A mutable reference to the CairoRunner instance.
    /// - `allocator`: The allocator to be used for initializing the ArrayList.
    ///
    /// # Returns
    /// An ArrayList containing information about the builtin segments.
    ///
    /// # Errors
    /// - Returns a RunnerError if any builtin runner does not have a stop pointer.
    pub fn getBuiltinSegmentsInfo(self: *Self, allocator: Allocator) !ArrayList(BuiltinInfo) {
        // Initialize an ArrayList to store information about builtin segments.
        var builtin_segment_info = ArrayList(BuiltinInfo).init(allocator);

        // Defer the deinitialization of the ArrayList to ensure cleanup in case of errors.
        errdefer builtin_segment_info.deinit();

        // Iterate through each builtin runner.
        for (self.vm.builtin_runners.items) |*builtin| {
            // Retrieve the memory segment addresses from the builtin runner.
            const memory_segment_addresses = builtin.getMemorySegmentAddresses();

            // Uncomment the following line for debugging purposes.
            // std.debug.print("memory_segment_addresses = {any}\n", .{memory_segment_addresses});

            // Check if the stop pointer is present.
            if (memory_segment_addresses[1]) |stop_pointer| {
                // Append information about the segment to the ArrayList.
                try builtin_segment_info.append(.{
                    .segment_index = memory_segment_addresses[0],
                    .stop_pointer = stop_pointer,
                });
            } else {
                // Return an error if a stop pointer is missing.
                return RunnerError.NoStopPointer;
            }
        }

        // Return the ArrayList containing information about the builtin segments.
        return builtin_segment_info;
    }

    pub fn deinit(self: *Self) void {
        // currently handling the deinit of the json.Parsed(ProgramJson) outside of constructor
        // otherwise the runner would always assume json in its interface
        // self.program.deinit();

        if (self.execution_public_memory) |execution_public_memory| execution_public_memory.deinit();

        self.instructions.deinit();
        self.layout.deinit();
        self.vm.deinit();
        self.relocated_memory.deinit();
    }
};

test "CairoRunner: initMainEntrypoint no main" {
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "all_cairo",
         ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    
    defer cairo_runner.deinit();

    // Add an OutputBuiltinRunner to the CairoRunner without setting the stop pointer.
    try cairo_runner.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) });

    if (cairo_runner.initMainEntrypoint()) |_| {
        return error.ExpectedError;
    } else |_| {}
}

test "CairoRunner: initVM should initialize the VM properly with no builtins" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",

        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure proper cleanup.
    defer cairo_runner.deinit();

    // Set initial values for program_base, initial_pc, initial_ap, and initial_fp.
    cairo_runner.program_base = Relocatable.init(0, 0);
    cairo_runner.initial_pc = Relocatable.init(0, 1);
    cairo_runner.initial_ap = Relocatable.init(1, 2);
    cairo_runner.initial_fp = Relocatable.init(1, 2);

    // Initialize the VM state using the initVM function.
    try cairo_runner.initVM();

    // Expect that the program counter (PC) is initialized correctly.
    try expectEqual(
        Relocatable.init(0, 1),
        cairo_runner.vm.run_context.pc.*,
    );
    // Expect that the allocation pointer (AP) is initialized correctly.
    try expectEqual(
        Relocatable.init(1, 2),
        cairo_runner.vm.run_context.ap.*,
    );
    // Expect that the frame pointer (FP) is initialized correctly.
    try expectEqual(
        Relocatable.init(1, 2),
        cairo_runner.vm.run_context.fp.*,
    );
}


test "CairoRunner: initVM should initialize the VM properly with Range Check builtin" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure proper cleanup.
    defer cairo_runner.deinit();

    // Append a RangeCheckBuiltinRunner to the CairoRunner's list of built-in runners.
    try cairo_runner.vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    // Set initial values for program_base, initial_pc, initial_ap, and initial_fp.
    cairo_runner.initial_pc = Relocatable.init(0, 1);
    cairo_runner.initial_ap = Relocatable.init(1, 2);
    cairo_runner.initial_fp = Relocatable.init(1, 2);

    // Initialize memory segments for the CairoRunner.
    try cairo_runner.initSegments(null);

    // Set up memory for the VM with specific addresses and values.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 2, 0 }, .{23} },
            .{ .{ 2, 1 }, .{233} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Expect that the name of the first built-in runner is "range_check_builtin".
    try expect(std.mem.eql(
        u8,
        cairo_runner.vm.builtin_runners.items[0].name(),
        "range_check_builtin",
    ));
    // Expect that the base address of the first built-in runner is 2.
    try expectEqual(
        @as(usize, 2),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );

    // Initialize the VM state using the initVM function.
    try cairo_runner.initVM();

    // Expect that the validated addresses in memory match the expected addresses.
    try expect(cairo_runner.vm.segments.memory.validated_addresses.contains(Relocatable.init(2, 0)));
    try expect(cairo_runner.vm.segments.memory.validated_addresses.contains(Relocatable.init(2, 1)));

    // Expect that the total number of validated addresses is 2.
    try expect(cairo_runner.vm.segments.memory.validated_addresses.len() == 2);
}

test "CairoRunner: initVM should return an error with invalid Range Check builtin" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure proper cleanup.
    defer cairo_runner.deinit();

    // Append a RangeCheckBuiltinRunner to the CairoRunner's list of built-in runners.
    try cairo_runner.vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    // Set initial values for program_base, initial_pc, initial_ap, and initial_fp.
    cairo_runner.initial_pc = Relocatable.init(0, 1);
    cairo_runner.initial_ap = Relocatable.init(1, 2);
    cairo_runner.initial_fp = Relocatable.init(1, 2);

    // Initialize memory segments for the CairoRunner.
    try cairo_runner.initSegments(null);

    // Set up memory for the VM with specific addresses and values.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 2, 0 }, .{23} },
        },
    );
    // Set an invalid value in memory for the Range Check builtin.
    try cairo_runner.vm.segments.memory.set(
        std.testing.allocator,
        Relocatable.init(2, 4),
        .{ .felt = Felt252.fromInt(u8, 1).neg() },
    );
    // Ensure data memory is deallocated after the test.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Expect an error of type RunnerError.MemoryValidationError when initializing the VM.
    try expectError(RunnerError.MemoryValidationError, cairo_runner.initVM());
}

test "RunResources: consumed and consumeStep" {
    // given
    const steps = 5;
    var run_resources = RunResources{ .n_steps = steps };
    var tracker = ResourceTracker.init(&run_resources);

    // Test initial state (not consumed)
    try expect(!tracker.consumed());

    // Consume a step and test
    tracker.consumeStep();
    try expect(run_resources.n_steps.? == steps - 1);

    // Consume remaining steps and test for consumed state
    var ran_steps: u32 = 0;
    while (!tracker.consumed()) : (ran_steps += 1) {
        tracker.consumeStep();
    }
    try expect(tracker.consumed());
    try expect(ran_steps == 4);
    try expect(run_resources.n_steps.? == 0);
}

test "RunResources: with unlimited steps" {
    // given
    var run_resources = RunResources{};

    // default case has null for n_steps
    try std.testing.expectEqual(null, run_resources.n_steps);

    var tracker = ResourceTracker.init(&run_resources);

    // Test that it's never consumed
    try std.testing.expect(!tracker.consumed());

    // Even after consuming steps, it should not be consumed
    tracker.consumeStep();
    tracker.consumeStep();
    try std.testing.expect(!tracker.consumed());
}

test "CairoRunner: getBuiltinSegmentsInfo with segment info empty should return an empty vector" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit();

    // Retrieve the builtin segment info from the CairoRunner.
    var builtin_segment_info = try cairo_runner.getBuiltinSegmentsInfo(std.testing.allocator);
    defer builtin_segment_info.deinit();

    // Ensure that the length of the vector is zero.
    try expect(builtin_segment_info.items.len == 0);
}

test "CairoRunner: getBuiltinSegmentsInfo info based not finished" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit();

    // Add an OutputBuiltinRunner to the CairoRunner without setting the stop pointer.
    try cairo_runner.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) });

    // Ensure that calling getBuiltinSegmentsInfo results in a RunnerError.NoStopPointer.
    try expectError(
        RunnerError.NoStopPointer,
        cairo_runner.getBuiltinSegmentsInfo(std.testing.allocator),
    );
}

test "CairoRunner: getBuiltinSegmentsInfo should provide builtin segment information" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit();

    // Create instances of OutputBuiltinRunner and BitwiseBuiltinRunner with stop pointers.
    var output_builtin = OutputBuiltinRunner.initDefault(std.testing.allocator);
    output_builtin.stop_ptr = 10;

    var bitwise_builtin = BitwiseBuiltinRunner{};
    bitwise_builtin.stop_ptr = 25;

    // Append instances of OutputBuiltinRunner and BitwiseBuiltinRunner to the CairoRunner.
    try cairo_runner.vm.builtin_runners.appendNTimes(.{ .Output = output_builtin }, 5);
    try cairo_runner.vm.builtin_runners.appendNTimes(.{ .Bitwise = bitwise_builtin }, 3);

    // Retrieve the builtin segment info from the CairoRunner.
    var builtin_segment_info = try cairo_runner.getBuiltinSegmentsInfo(std.testing.allocator);
    defer builtin_segment_info.deinit();

    // Verify that the obtained information matches the expected values.
    try expectEqualSlices(
        BuiltinInfo,
        &[_]BuiltinInfo{
            .{ .segment_index = 0, .stop_pointer = 10 },
            .{ .segment_index = 0, .stop_pointer = 10 },
            .{ .segment_index = 0, .stop_pointer = 10 },
            .{ .segment_index = 0, .stop_pointer = 10 },
            .{ .segment_index = 0, .stop_pointer = 10 },
            .{ .segment_index = 0, .stop_pointer = 25 },
            .{ .segment_index = 0, .stop_pointer = 25 },
            .{ .segment_index = 0, .stop_pointer = 25 },
        },
        builtin_segment_info.items,
    );
}

test "CairoRunner: relocateMemory should relocated memory properly with gaps" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Ensure CairoRunner resources are cleaned up.
    defer cairo_runner.deinit();

    // Create four memory segments in the VM.
    inline for (0..4) |_| {
        _ = try cairo_runner.vm.segments.addSegment();
    }

    // Set up memory in the VM segments with gaps.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{4613515612218425347} },
            .{ .{ 0, 1 }, .{5} },
            .{ .{ 0, 2 }, .{2345108766317314046} },
            .{ .{ 1, 0 }, .{ 2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
            .{ .{ 1, 5 }, .{5} },
        },
    );
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Compute the effective size of the VM segments.
    _ = try cairo_runner.vm.segments.computeEffectiveSize(false);

    // Relocate the segments and obtain the relocation table.
    const relocation_table = try cairo_runner.vm.segments.relocateSegments(std.testing.allocator);
    defer std.testing.allocator.free(relocation_table);

    // Call the `relocateMemory` function.
    try cairo_runner.relocateMemory(relocation_table);

    // Perform assertions to check if memory relocation is correct.
    try expectEqualSlices(
        ?Felt252,
        &[_]?Felt252{
            null,
            Felt252.fromInt(u256, 4613515612218425347),
            Felt252.fromInt(u8, 5),
            Felt252.fromInt(u256, 2345108766317314046),
            Felt252.fromInt(u8, 10),
            Felt252.fromInt(u8, 10),
            null,
            null,
            null,
            Felt252.fromInt(u8, 5),
        },
        cairo_runner.relocated_memory.items,
    );
}

test "CairoRunner: initSegments should initialize the segments properly with base" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit();

    // Append an OutputBuiltinRunner to the CairoRunner's list of built-in runners.
    try cairo_runner.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) });

    // Add six additional segments to the CairoRunner's virtual machine.
    inline for (0..6) |_| {
        _ = try cairo_runner.vm.segments.addSegment();
    }

    // Initialize the segments for the CairoRunner with a provided base address (Relocatable).
    try cairo_runner.initSegments(Relocatable.init(5, 9));

    // Expect that the program base is initialized correctly.
    try expectEqual(
        Relocatable.init(5, 9),
        cairo_runner.program_base,
    );
    // Expect that the execution base is initialized correctly.
    try expectEqual(
        Relocatable.init(6, 0),
        cairo_runner.execution_base,
    );
    // Expect that the name of the first built-in runner is "output_builtin".
    try expect(std.mem.eql(
        u8,
        cairo_runner.vm.builtin_runners.items[0].name(),
        "output_builtin",
    ));
    // Expect that the base address of the first built-in runner is 7.
    try expectEqual(
        @as(usize, 7),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );
    // Expect that the total number of segments in the virtual machine is 8.
    try expectEqual(
        @as(usize, 8),
        cairo_runner.vm.segments.numSegments(),
    );
}

test "CairoRunner: initSegments should initialize the segments properly with no base" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        ProgramJson{},
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit();

    // Append an OutputBuiltinRunner to the CairoRunner's list of built-in runners.
    try cairo_runner.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) });

    // Initialize the segments for the CairoRunner with no provided base address (null).
    try cairo_runner.initSegments(null);

    // Expect that the program base is initialized correctly to (0, 0).
    try expectEqual(
        Relocatable.init(0, 0),
        cairo_runner.program_base,
    );
    // Expect that the execution base is initialized correctly to (1, 0).
    try expectEqual(
        Relocatable.init(1, 0),
        cairo_runner.execution_base,
    );
    // Expect that the name of the first built-in runner is "output_builtin".
    try expect(std.mem.eql(
        u8,
        cairo_runner.vm.builtin_runners.items[0].name(),
        "output_builtin",
    ));
    // Expect that the base address of the first built-in runner is 2.
    try expectEqual(
        @as(usize, 2),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );
    // Expect that the total number of segments in the virtual machine is 3.
    try expectEqual(
        @as(usize, 3),
        cairo_runner.vm.segments.numSegments(),
    );
}
