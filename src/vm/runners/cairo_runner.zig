const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const MemoryCell = @import("../memory/memory.zig").MemoryCell;
const HintData = @import("../../hint_processor/hint_processor_def.zig").HintData;
const HintReference = @import("../../hint_processor/hint_processor_def.zig").HintReference;
const HintProcessor = @import("../../hint_processor/hint_processor_def.zig").CairoVMHintProcessor;
const BuiltinRunner = @import("../builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const Config = @import("../config.zig").Config;
const CairoVM = @import("../core.zig").CairoVM;
const CairoLayout = @import("../types/layout.zig").CairoLayout;
const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const Program = @import("../types/program.zig").Program;
const BuiltinName = @import("../types/programjson.zig").BuiltinName;
const ProgramJson = @import("../types/programjson.zig").ProgramJson;
const builtin_runner_import = @import("../builtins/builtin_runner/builtin_runner.zig");
const HintRange = @import("../types/program.zig").HintRange;
const HintParams = @import("../types/programjson.zig").HintParams;
const Identifier = @import("../types/programjson.zig").Identifier;
const Attribute = @import("../types/programjson.zig").Attribute;
const ReferenceManager = @import("../types/programjson.zig").ReferenceManager;
const CairoRunnerError = @import("../error.zig").CairoRunnerError;
const MathError = @import("../error.zig").MathError;
const CairoVMError = @import("../error.zig").CairoVMError;
const InsufficientAllocatedCellsError = @import("../error.zig").InsufficientAllocatedCellsError;
const RunnerError = @import("../error.zig").RunnerError;
const MemoryError = @import("../error.zig").MemoryError;
const trace_context = @import("../trace_context.zig");
const RelocatedTraceEntry = trace_context.RelocatedTraceEntry;
const starknet_felt = @import("../../math/fields/starknet.zig");
const Felt252 = starknet_felt.Felt252;
const ExecutionScopes = @import("../types/execution_scopes.zig").ExecutionScopes;
const TraceEntry = @import("../trace_context.zig").TraceEntry;
const TestingUtils = @import("../../utils/testing.zig");

const OutputBuiltinRunner = @import("../builtins/builtin_runner/output.zig").OutputBuiltinRunner;
const BitwiseBuiltinRunner = @import("../builtins/builtin_runner/bitwise.zig").BitwiseBuiltinRunner;
const RangeCheckBuiltinRunner = @import("../builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;
const HashBuiltinRunner = @import("../builtins/builtin_runner/hash.zig").HashBuiltinRunner;
const SignatureBuiltinRunner = @import("../builtins/builtin_runner/signature.zig").SignatureBuiltinRunner;
const EcOpBuiltinRunner = @import("../builtins/builtin_runner/ec_op.zig").EcOpBuiltinRunner;
const KeccakBuiltinRunner = @import("../builtins/builtin_runner/keccak.zig").KeccakBuiltinRunner;
const PoseidonBuiltinRunner = @import("../builtins/builtin_runner/poseidon.zig").PoseidonBuiltinRunner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Tracks the step resources of a cairo execution run.
pub const RunResources = struct {
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

    program: Program,
    allocator: Allocator,
    vm: CairoVM,
    program_base: ?Relocatable = null,
    execution_base: ?Relocatable = null,
    initial_pc: ?Relocatable = null,
    initial_ap: ?Relocatable = null,
    initial_fp: ?Relocatable = null,
    final_pc: ?Relocatable = null,
    instructions: std.ArrayList(MaybeRelocatable),
    // function_call_stack: std.ArrayList(MaybeRelocatable),
    entrypoint: ?usize,
    layout: CairoLayout,
    runner_mode: RunnerMode,
    run_ended: bool = false,
    execution_public_memory: ?std.ArrayList(usize) = null,
    relocated_trace: ?[]RelocatedTraceEntry = null,
    relocated_memory: ArrayList(?Felt252),
    execution_scopes: ExecutionScopes = undefined,

    pub fn init(
        allocator: Allocator,
        program: Program,
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
            .execution_scopes = try ExecutionScopes.init(allocator),
            .entrypoint = program.shared_program_data.main,
        };
    }

    pub fn isProofMode(self: *Self) bool {
        return self.runner_mode == .proof_mode_canonical or self.runner_mode == .proof_mode_cairo1;
    }

    pub fn initBuiltins(self: *Self, allow_missing_builtins: bool) !void {
        var program_builtins = std.AutoHashMap(BuiltinName, void).init(self.allocator);
        defer program_builtins.deinit();

        for (self.program.builtins.items) |builtin| {
            try program_builtins.put(builtin, undefined);
        }

        // check if program builtins in right order
        {
            var builtin_ordered_list: []const BuiltinName = &.{
                .output,
                .pedersen,
                .range_check,
                .ecdsa,
                .bitwise,
                .ec_op,
                .keccak,
                .poseidon,
            };

            for (self.program.builtins.items) |builtin| {
                var found = false;

                for (builtin_ordered_list, 0..) |ord_builtin, idx| {
                    if (builtin == ord_builtin) {
                        found = true;
                        builtin_ordered_list = builtin_ordered_list[idx + 1 ..];
                        break;
                    }
                }

                if (!found) return RunnerError.DisorderedBuiltins;
            }
        }

        if (self.layout.builtins.output) {
            const included = program_builtins.remove(.output);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.init(self.allocator, included) });
        }

        if (self.layout.builtins.pedersen) |pedersen_def| {
            const included = program_builtins.remove(.pedersen);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{
                    .Hash = HashBuiltinRunner.init(self.allocator, pedersen_def.ratio, included),
                });
        }

        if (self.layout.builtins.range_check) |instance_def| {
            const included = program_builtins.remove(.range_check);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{
                    .RangeCheck = RangeCheckBuiltinRunner.init(instance_def.ratio, instance_def.n_parts, included),
                });
        }

        if (self.layout.builtins.ecdsa) |instance_def| {
            const included = program_builtins.remove(.ecdsa);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{
                    .Signature = SignatureBuiltinRunner.init(self.allocator, &instance_def, included),
                });
        }

        if (self.layout.builtins.bitwise) |instance_def| {
            const included = program_builtins.remove(.bitwise);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{
                    .Bitwise = BitwiseBuiltinRunner.init(&instance_def, included),
                });
        }

        if (self.layout.builtins.ec_op) |instance_def| {
            const included = program_builtins.remove(.ec_op);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{
                    .EcOp = EcOpBuiltinRunner.init(self.allocator, instance_def, included),
                });
        }

        if (self.layout.builtins.keccak) |instance_def| {
            const included = program_builtins.remove(.keccak);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{
                    .Keccak = try KeccakBuiltinRunner.init(self.allocator, &instance_def, included),
                });
        }

        if (self.layout.builtins.poseidon) |instance_def| {
            const included = program_builtins.remove(.poseidon);

            if (included or self.isProofMode())
                try self.vm.builtin_runners.append(.{
                    .Poseidon = PoseidonBuiltinRunner.init(self.allocator, instance_def.ratio, included),
                });
        }

        if (program_builtins.count() != 0 and !allow_missing_builtins)
            return RunnerError.NoBuiltinForInstance;
    }

    pub fn setupExecutionState(self: *Self, allow_missing_builtins: bool) !Relocatable {
        try self.initBuiltins(allow_missing_builtins);
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

    /// Initializes the runner state for execution.
    ///
    /// This function sets up the initial state of the Cairo runner for execution. It initializes
    /// the program counter, loads instructions into the program segment, and loads the function
    /// call stack into the execution segment.
    ///
    /// # Arguments
    ///
    /// - `entrypoint`: The address, relative to the program segment, where execution begins.
    /// - `stack`: A pointer to the ArrayList(MaybeRelocatable) representing the function call stack.
    ///
    /// # Returns
    ///
    /// This function returns void.
    pub fn initState(self: *Self, entrypoint: usize, stack: *std.ArrayList(MaybeRelocatable)) !void {
        // Check if the program base is initialized.
        if (self.program_base) |pb| {
            // Set the initial program counter.
            self.initial_pc = try pb.addInt(@intCast(entrypoint));

            // Load program data into the program base segment.
            _ = self.vm.loadData(
                pb,
                &self.program.shared_program_data.data,
            ) catch return RunnerError.MemoryInitializationError;

            // Mark memory addresses in the program base segment as accessed.
            for (0..self.program.shared_program_data.data.items.len) |i|
                self.vm.segments.memory.markAsAccessed(try pb.addUint(i));
        }

        // Check if the execution base is initialized.
        if (self.execution_base) |eb| {
            // Load the function call stack into the execution base segment.
            _ = self.vm.segments.loadData(self.allocator, eb, stack.items) catch
                return RunnerError.MemoryInitializationError;
        } else {
            // Return an error if the execution base is not initialized.
            return RunnerError.NoProgBase;
        }
    }

    pub fn initFunctionEntrypoint(
        self: *Self,
        entrypoint: usize,
        return_fp: MaybeRelocatable,
        stack: *std.ArrayList(MaybeRelocatable),
    ) !Relocatable {
        const end = try self.vm.segments.addSegment();

        // per 6.1 of cairo whitepaper
        // a call stack usually increases a frame when a function is called
        // and decreases when a function returns,
        // but to situate the functionality with Cairo's read-only memory,
        // the frame pointer register is used to point to the current frame in the stack
        // the runner sets the return fp and establishes the end address that execution treats as the endpoint.
        try stack.append(return_fp);
        try stack.append(MaybeRelocatable.fromRelocatable(end));

        if (self.execution_base) |b| {
            self.initial_fp = Relocatable.init(b.segment_index, b.offset + stack.items.len);
            self.initial_ap = self.initial_fp;
        } else return RunnerError.NoExecBase;

        try self.initState(entrypoint, stack);
        self.final_pc = end;
        return end;
    }

    /// Initializes runner state for execution of a program from the `main()` entrypoint.
    ///
    /// This function prepares the runner state for executing a program starting from the `main()` entrypoint. It sets up the initial stack and state variables required for execution, depending on whether the runner is in proof mode or not.
    ///
    /// # Returns
    ///
    /// Returns a `Relocatable` representing the program end if the initialization is successful. Otherwise, it returns an error indicating the reason for failure.
    pub fn initMainEntrypoint(self: *Self) !Relocatable {
        // Initialize stack for storing execution context.
        var stack = std.ArrayList(MaybeRelocatable).init(self.allocator);
        defer stack.deinit();

        // Initialize stack with initial values from built-in runners.
        for (self.vm.builtin_runners.items) |*builtin_runner| {
            const builtin_stack = try builtin_runner.initialStack(self.allocator);
            defer builtin_stack.deinit();

            try stack.appendSlice(builtin_stack.items);
        }

        // If in proof mode, prepare execution state with additional adjustments.
        if (self.isProofMode()) {
            var target_offset: usize = 2;

            // If in canonical proof mode, adjust stack and execution state accordingly.
            if (self.runner_mode == .proof_mode_canonical) {
                // Prepare stack prefix with additional execution context.
                var stack_prefix = try std.ArrayList(MaybeRelocatable).initCapacity(self.allocator, 2 + stack.items.len);
                defer stack_prefix.deinit();

                try stack_prefix.append(MaybeRelocatable.fromRelocatable(
                    try (self.execution_base orelse return RunnerError.NoExecBase).addUint(target_offset),
                ));
                try stack_prefix.append(MaybeRelocatable.fromFelt(Felt252.zero()));
                try stack_prefix.appendSlice(stack.items);

                // Initialize public memory for execution context.
                var execution_public_memory = try std.ArrayList(usize).initCapacity(self.allocator, stack_prefix.items.len);

                for (0..stack_prefix.items.len) |v| {
                    try execution_public_memory.append(v);
                }

                self.execution_public_memory = execution_public_memory;

                // Initialize execution state with adjusted stack prefix.
                try self.initState(try (self.program.shared_program_data.start orelse
                    RunnerError.NoProgramStart), &stack_prefix);
            } else {
                // Adjust target offset and stack length for proof mode.
                target_offset = stack.items.len + 2;

                // Add return frame pointer and end marker to stack.
                const return_fp = try self.vm.segments.addSegment();
                const end = try self.vm.segments.addSegment();
                try stack.append(MaybeRelocatable.fromRelocatable(return_fp));
                try stack.append(MaybeRelocatable.fromRelocatable(end));

                // Initialize execution state with adjusted stack.
                try self.initState(try (self.program.shared_program_data.start orelse
                    RunnerError.NoProgramStart), &stack);
            }

            // Set initial frame pointer and argument pointer.
            self.initial_fp = try (self.execution_base orelse return RunnerError.NoExecBase).addUint(target_offset);
            self.initial_ap = self.initial_fp;

            // Return program end address.
            return (self.program_base orelse
                return RunnerError.NoExecBase).addUint(try (self.program.shared_program_data.end orelse
                RunnerError.NoProgramEnd));
        }

        // If not in proof mode, set up return frame pointer.
        const return_fp = try self.vm.segments.addSegment();

        // If a custom entrypoint is specified, initialize execution from the entrypoint.
        if (self.entrypoint) |main|
            return self.initFunctionEntrypoint(
                main,
                MaybeRelocatable.fromRelocatable(return_fp),
                &stack,
            );

        // If no custom entrypoint is specified, return an error.
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
        self.vm.run_context.ap.* = (self.initial_ap orelse return RunnerError.NoAP).offset;
        self.vm.run_context.fp.* = (self.initial_fp orelse return RunnerError.NoFP).offset;
        self.vm.run_context.pc.* = self.initial_pc orelse return RunnerError.NoPC;

        // Add validation rules for built-in runners
        for (self.vm.builtin_runners.items) |*builtin_runner| {
            try builtin_runner.addValidationRule(self.vm.segments.memory);
        }

        // Validate existing memory segments
        self.vm.segments.memory.validateExistingMemory() catch return RunnerError.MemoryValidationError;
    }

    /// Gets the data used by the HintProcessor to execute each hint
    pub fn getHintData(self: *Self, hint_processor: *HintProcessor, references: []HintReference) !std.ArrayList(HintData) {
        var result = std.ArrayList(HintData).init(self.allocator);
        errdefer result.deinit();

        for (self.program.shared_program_data.hints_collection.hints.items) |hint| {
            //// TODO: improve this part, because of std.json.arrayhashmap
            var reference_ids = std.StringHashMap(usize).init(self.allocator);
            defer reference_ids.deinit();

            var it = hint.flow_tracking_data.reference_ids.?.map.iterator();

            while (it.next()) |ref_id_en|
                try reference_ids.put(ref_id_en.key_ptr.*, ref_id_en.value_ptr.*);
            // end part

            try result.append(
                try (hint_processor.compileHint(
                    self.allocator,
                    hint.code,
                    hint.flow_tracking_data.ap_tracking,
                    reference_ids,
                    references,
                ) catch CairoVMError.CompileHintFail),
            );
        }

        return result;
    }

    pub fn runUntilPC(
        self: *Self,
        end: Relocatable,
        extensive_hints: bool,
        hint_processor: *HintProcessor,
    ) !void {
        const references = self.program.shared_program_data.reference_manager.items;

        var hint_datas = try self.getHintData(hint_processor, references);
        defer hint_datas.deinit();

        var hint_ranges: std.AutoHashMap(Relocatable, HintRange) = undefined;
        defer {
            if (extensive_hints) hint_ranges.deinit();
        }

        if (extensive_hints)
            hint_ranges = try self.program.shared_program_data
                .hints_collection.hints_ranges.Extensive.clone();

        while (!end.eq(self.vm.run_context.pc.*) and !hint_processor.run_resources.consumed()) {
            if (extensive_hints) {
                try self.vm.stepExtensive(
                    self.allocator,
                    hint_processor.*,
                    &self.execution_scopes,
                    &hint_datas,
                    &hint_ranges,
                    &self.program.constants,
                );
            } else {
                try self.vm.stepNotExtensive(
                    self.allocator,
                    hint_processor.*,
                    &self.execution_scopes,
                    if (self.program
                        .shared_program_data
                        .hints_collection
                        .getHintRangeForPC(self.vm.run_context.pc.offset)) |range|
                        hint_datas.items[range.start .. range.start + range.length]
                    else
                        &.{},
                    &self.program.constants,
                );
            }

            hint_processor.run_resources.consumeStep();
        }
    }

    /// Executes the Cairo program until the number of steps reaches the next power of two.
    ///
    /// This function runs the Cairo program until the number of executed steps reaches the next power of two.
    /// It internally calculates the next power of two based on the current step count and then invokes
    /// the `runUntilSteps` function to execute the program up to that step count.
    ///
    /// # Arguments
    ///
    /// - `extensive_hints`: A boolean indicating whether extensive hints should be enabled during execution.
    /// - `hint_processor`: A pointer to the HintProcessor instance responsible for processing hints during execution.
    ///
    /// # Returns
    ///
    /// This function returns `void` upon successful execution. In case of errors or if the program execution
    /// reaches the end, it may return a `CairoVMError`.
    pub fn runUntilNextPowerOf2(
        self: *Self,
        extensive_hints: bool,
        hint_processor: *HintProcessor,
    ) !void {
        // Calculate the next power of two for the current step count
        const next_power_of_two_steps = try std.math.ceilPowerOfTwo(usize, self.vm.current_step);

        // Run the program until the next power of two steps
        try self.runUntilSteps(next_power_of_two_steps, extensive_hints, hint_processor);
    }

    /// Executes the Cairo program until a specified number of steps is reached.
    ///
    /// This function runs the Cairo program until a specified number of steps is reached.
    /// It calculates the remaining steps needed based on the current step count and invokes
    /// the `runForSteps` function to execute the program for the required number of steps.
    ///
    /// # Arguments
    ///
    /// - `steps`: The total number of steps to run the program for.
    /// - `extensive_hints`: A boolean indicating whether extensive hints should be enabled during execution.
    /// - `hint_processor`: A pointer to the HintProcessor instance responsible for processing hints during execution.
    ///
    /// # Returns
    ///
    /// This function returns `void` upon successful execution. In case of errors or if the program execution
    /// reaches the end, it may return a `CairoVMError`.
    pub fn runUntilSteps(
        self: *Self,
        steps: usize,
        extensive_hints: bool,
        hint_processor: *HintProcessor,
    ) !void {
        // Calculate the remaining steps needed based on the current step count
        const remaining_steps = steps -| self.vm.current_step;

        // Run the program for the remaining steps
        try self.runForSteps(remaining_steps, extensive_hints, hint_processor);
    }

    /// Executes the Cairo program for a specified number of steps.
    ///
    /// This function runs the Cairo program for a given number of steps, considering each step as an instruction
    /// executed by the virtual machine (VM). It allows the program to progress within the VM's execution until
    /// the specified number of steps is reached or until the program execution finishes.
    ///
    /// # Arguments
    ///
    /// - `steps`: The number of steps to run the program for.
    /// - `extensive_hints`: A boolean indicating whether extensive hints should be enabled during execution.
    /// - `hint_processor`: A pointer to the HintProcessor instance responsible for processing hints during execution.
    ///
    /// # Returns
    ///
    /// This function returns `void` upon successful execution. In case of errors or if the program execution
    /// reaches the end, it may return a `CairoVMError`.
    pub fn runForSteps(
        self: *Self,
        steps: usize,
        extensive_hints: bool,
        hint_processor: *HintProcessor,
    ) !void {
        // Get references for hint processing
        const references = self.program.shared_program_data.reference_manager.items;

        // Get hint data required for hint processing
        var hint_datas = try self.getHintData(hint_processor, references);
        defer hint_datas.deinit();

        // Prepare hint ranges for extensive hint processing
        var hint_ranges: std.AutoHashMap(Relocatable, HintRange) = undefined;
        defer {
            if (extensive_hints) hint_ranges.deinit();
        }

        // Clone extensive hint ranges if extensive hints are enabled
        if (extensive_hints)
            hint_ranges = try self.program.shared_program_data
                .hints_collection.hints_ranges.Extensive.clone();

        // Prepare final hint data for non-extensive hint processing
        var hint_data_final: []HintData = &.{};

        // If extensive hints are not enabled, determine the hint data for the current PC offset
        if (!extensive_hints) {
            if (self.program
                .shared_program_data
                .hints_collection
                .getHintRangeForPC(self.vm.run_context.pc.offset)) |range|
                hint_data_final = hint_datas.items[range.start .. range.start + range.length];
        }
        // Initialize remaining steps to run
        var remaining_steps: usize = steps;

        // Loop until all steps are executed or program ends
        while (remaining_steps >= 1) {
            // Check if the program has reached its end
            if (self.final_pc.?.eq(self.vm.run_context.pc.*))
                return CairoVMError.EndOfProgram;

            // Execute a single step of the program, considering extensive or non-extensive hints
            if (extensive_hints) {
                try self.vm.stepExtensive(
                    self.allocator,
                    hint_processor.*,
                    &self.execution_scopes,
                    &hint_datas,
                    &hint_ranges,
                    &self.program.constants,
                );
            } else {
                try self.vm.stepNotExtensive(
                    self.allocator,
                    hint_processor.*,
                    &self.execution_scopes,
                    hint_data_final,
                    &self.program.constants,
                );
            }

            // Decrement remaining steps
            remaining_steps -= 1;
        }
    }

    /// Checks the used cells and allocated memory size of the virtual machine (VM) and performs memory usage checks.
    ///
    /// This method checks the used cells and allocated memory size of the VM, including built-in runners, and performs various memory usage checks.
    /// It utilizes an allocator to manage memory and stores the results in an ArrayList.
    ///
    /// # Arguments
    ///
    /// - `allocator`: The allocator used for managing memory.
    ///
    /// # Returns
    ///
    /// This function returns `void` upon successful execution. In case of errors during memory checks, it may return specific error types.
    pub fn checkUsedCells(self: *Self, allocator: Allocator) !void {
        // Initialize ArrayList to store results
        var res = std.ArrayList(std.meta.Tuple(&.{ usize, ?usize })).init(allocator);
        defer res.deinit(); // Deallocate ArrayList memory upon function exit

        // Iterate over built-in runners and retrieve used cells and allocated size information
        for (self.vm.builtin_runners.items) |builtin| {
            try res.append(try builtin.getUsedCellsAndAllocatedSize(&self.vm));
        }

        // Perform various memory usage checks
        try self.checkRangeCheckUsage(allocator, &self.vm);
        try self.checkMemoryUsage();
        try self.checkDilutedCheckUsage(allocator);
    }

    /// Checks the memory usage of the virtual machine (VM) and performs memory-related calculations.
    ///
    /// This method checks the memory usage of the VM, including built-in runners, and performs various memory-related calculations.
    /// It calculates the total memory units available per step, fraction used for public memory, instruction memory units,
    /// unused memory units, and memory address holes, and compares them to ensure sufficient allocated cells.
    ///
    /// # Returns
    ///
    /// This function returns `void` upon successful execution. In case of memory-related errors, it may return specific error types.
    pub fn checkMemoryUsage(self: *Self) !void {
        // Retrieve instance reference
        const instance = &self.layout;

        // Initialize variable to store built-in memory units
        var builtins_memory_units: u32 = 0;

        // Iterate over built-in runners and calculate allocated memory units
        for (self.vm.builtin_runners.items) |builtin| {
            builtins_memory_units += @intCast(try builtin.getAllocatedMemoryUnits(&self.vm));
        }

        // Retrieve current step of the VM
        const vm_current_step: u32 = @intCast(self.vm.current_step);

        // Calculate total memory units available per step
        const total_memory_units = instance.memory_units_per_step * vm_current_step;

        // Ensure safe division for public memory fraction
        if (@rem(total_memory_units, instance.public_memory_fraction) != 0)
            return MathError.SafeDivFailU32;

        // Calculate instruction memory units
        const instruction_memory_units = 4 * vm_current_step;

        // Calculate unused memory units
        const unused_memory_units = total_memory_units -
            (total_memory_units / instance.public_memory_fraction +
            instruction_memory_units + builtins_memory_units);

        // Retrieve memory address holes
        const memory_address_holes = try self.getMemoryHoles();

        // Check for insufficient allocated cells
        if (unused_memory_units < memory_address_holes)
            return MemoryError.InsufficientAllocatedCells;
    }

    /// Ends the execution of the Cairo program, performing various cleanup operations and finalizations.
    ///
    /// This method concludes the execution of the Cairo program, performing memory relocation, finalizing VM execution,
    /// and optionally padding execution traces in proof mode.
    ///
    /// # Arguments
    ///
    /// - `allocator`: The allocator used for managing memory.
    /// - `disable_trace_padding`: A boolean indicating whether to disable trace padding in proof mode.
    /// - `disable_finalize_all`: A boolean indicating whether to disable finalization of all segments.
    /// - `hint_processor`: A pointer to the HintProcessor instance responsible for processing hints during execution.
    /// - `extensive_hints`: A boolean indicating whether extensive hints should be enabled during execution.
    ///
    /// # Returns
    ///
    /// This function returns `void` upon successful execution. In case of errors or if the method has already been called,
    /// it may return specific error types.
    pub fn endRun(
        self: *Self,
        allocator: Allocator,
        disable_trace_padding: bool,
        disable_finalize_all: bool,
        hint_processor: *HintProcessor,
        extensive_hints: bool,
    ) !void {
        // Check if the method has already been called
        if (self.run_ended)
            return CairoRunnerError.EndRunAlreadyCalled;

        // Perform memory relocation
        try self.vm.segments.memory.relocateMemory();

        // Finalize VM execution
        try self.vm.endRun(allocator, &self.execution_scopes);

        // Return if finalization of all segments is disabled
        if (disable_finalize_all) return;

        // Compute effective sizes of segments
        _ = try self.vm.computeSegmentsEffectiveSizes(false);

        // Perform trace padding in proof mode if not disabled
        if (self.isProofMode() and !disable_trace_padding) {
            // Run until the next power of 2 is reached
            try self.runUntilNextPowerOf2(extensive_hints, hint_processor);

            // Loop until sufficient allocated cells are available
            while (true) {
                // Check used cells and handle errors
                if (self.checkUsedCells(allocator)) {
                    break;
                } else |err| switch (err) {
                    MemoryError.InsufficientAllocatedCells => {},
                    InsufficientAllocatedCellsError.BuiltinCells => {},
                    InsufficientAllocatedCellsError.DilutedCells => {},
                    InsufficientAllocatedCellsError.MemoryAddresses => {},
                    InsufficientAllocatedCellsError.MinStepNotReached => {},
                    InsufficientAllocatedCellsError.RangeCheckUnits => {},
                    else => |e| return e,
                }

                // Run for one step and continue padding traces
                try self.runForSteps(1, extensive_hints, hint_processor);
                try self.runUntilNextPowerOf2(extensive_hints, hint_processor);
            }
        }

        // Mark the end of the run
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
        defer self.allocator.free(relocation_table);

        try self.relocateMemory(relocation_table);
        if (self.vm.trace != null) {
            try self.vm.relocateTrace(relocation_table);
            self.relocated_trace = try self.vm.getRelocatedTrace();
        }
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

    /// Checks that there are enough trace cells to fill the entire range check
    /// range.
    pub fn checkRangeCheckUsage(self: *Self, allocator: Allocator, vm: *CairoVM) !void {
        const rc_min_max = (try self.getPermRangeCheckLimits(allocator)) orelse return;
        var rc_units_used_by_builtins: usize = 0;

        for (vm.builtin_runners.items) |runner|
            rc_units_used_by_builtins = rc_units_used_by_builtins + try runner.getUsedPermRangeCheckUnits(vm);

        const unused_rc_units = (@as(usize, self.layout.rc_units) - 3) * vm.current_step - rc_units_used_by_builtins;

        if (unused_rc_units < @as(usize, @intCast(rc_min_max[1] - rc_min_max[0])))
            return InsufficientAllocatedCellsError.RangeCheckUnits;
    }

    /// Retrieves the number of memory holes in the CairoRunner's virtual machine (VM) segments.
    ///
    /// Memory holes are regions of memory that are unused or uninitialized.
    /// This function calculates the number of memory holes based on the VM's segments
    /// and the presence of certain built-in runners.
    ///
    /// # Arguments
    ///
    /// - `self`: A mutable reference to the CairoRunner instance.
    ///
    /// # Returns
    ///
    /// The number of memory holes in the VM segments.
    ///
    /// # Errors
    ///
    /// - Returns a `MemoryError` if any errors occur during the calculation.
    pub fn getMemoryHoles(self: *Self) !usize {
        // Check if the program has the output builtin
        var has_output_builtin: bool = false;
        for (self.program.builtins.items) |builtin| {
            if (builtin == .output) has_output_builtin = true;
        }

        // Calculate memory holes based on VM segments and built-in runners
        return self.vm.segments.getMemoryHoles(
            self.vm.builtin_runners.items.len,
            has_output_builtin,
        );
    }

    /// Retrieves the permanent range check limits from the CairoRunner instance.
    ///
    /// This function iterates through the builtin runners of the CairoRunner and gathers
    /// information about the range check usage. It considers both the range check usage
    /// provided by the builtin runners and any range check limits specified in the VM configuration.
    /// The function calculates the minimum range check limits from all sources and returns them.
    ///
    /// # Arguments
    /// - `self`: A mutable reference to the CairoRunner instance.
    /// - `allocator`: The allocator to be used for initializing internal data structures.
    ///
    /// # Returns
    /// An optional tuple containing the minimum permanent range check limits.
    /// If no range check limits are found, it returns `null`.
    pub fn getPermRangeCheckLimits(self: *Self, allocator: Allocator) !?std.meta.Tuple(&.{ isize, isize }) {

        // Initialize an ArrayList to store information about builtin segments.
        var runner_usages = ArrayList(std.meta.Tuple(&.{ isize, isize })).init(allocator);

        // Defer the deinitialization of the ArrayList to ensure cleanup in case of errors.
        defer runner_usages.deinit();

        // Iterate through each builtin runner to collect range check usage.
        for (self.vm.builtin_runners.items) |builtin| {
            // Check if the builtin runner provides range check usage information.
            if (builtin.getRangeCheckUsage(self.vm.segments.memory)) |rc| {
                // Append the range check usage tuple to the ArrayList.
                try runner_usages.append(.{ @intCast(rc[0]), @intCast(rc[1]) });
            }
        }

        // Check if the VM configuration specifies range check limits.
        if (self.vm.rc_limits) |rc| {
            // Append the range check limits from the VM configuration to the ArrayList.
            try runner_usages.append(rc);
        }

        // If no range check usage information is available, return null.
        if (runner_usages.items.len == 0) {
            return null;
        }

        // Initialize the result tuple with the range check limits from the VM configuration
        // or the first builtin runner, whichever is available.
        var res: std.meta.Tuple(&.{ isize, isize }) = self.vm.rc_limits orelse runner_usages.items[0];

        // Iterate through each range check usage tuple to find the minimum limits.
        for (runner_usages.items) |runner_usage| {
            // Update the result tuple with the minimum limits.
            res[0] = @min(res[0], runner_usage[0]);
            res[1] = @max(res[1], runner_usage[1]);
        }

        // Return the minimum permanent range check limits.
        return res;
    }

    /// Checks the diluted check usage to ensure sufficient allocation of memory units.
    ///
    /// This method calculates the amount of memory units used by the built-in runners
    /// for diluted checks and verifies if it meets the required upper bound.
    ///
    /// # Arguments
    ///
    /// - `self`: A mutable reference to the CairoRunner instance.
    /// - `allocator`: The allocator to be used for memory allocation.
    ///
    /// # Returns
    ///
    /// This method does not return a value, but it may panic if insufficient memory units are allocated.
    ///
    /// # Errors
    ///
    /// - Panics with a `MemoryError` if the allocated memory units for diluted checks are insufficient.
    pub fn checkDilutedCheckUsage(self: *Self, allocator: Allocator) !void {
        // Check if diluted pool instance is defined
        if (self.layout.diluted_pool_instance_def) |diluted_pool_instance| {
            var used_units_by_builtins: usize = 0;

            // Iterate through each built-in runner
            for (self.vm.builtin_runners.items) |*builtin_runner| {
                // Calculate the used units by the built-in runner for diluted checks
                const used_units = try builtin_runner.getUsedDilutedCheckUnits(
                    allocator,
                    diluted_pool_instance.spacing,
                    diluted_pool_instance.n_bits,
                );

                // Calculate the multiplier based on the current step and the runner's ratio
                const multiplier = try std.math.divExact(
                    usize,
                    self.vm.current_step,
                    builtin_runner.ratio() orelse 1,
                );

                // Update the total used units by built-ins
                used_units_by_builtins += used_units * multiplier;
            }

            // Calculate the total diluted units based on the diluted pool instance and the current step
            const diluted_units = @as(
                usize,
                @intCast(diluted_pool_instance.units_per_step),
            ) * self.vm.current_step;

            // Calculate the unused diluted units
            const unused_diluted_units = diluted_units -| used_units_by_builtins;

            // Calculate the upper bound for diluted check usage
            const diluted_usage_upper_bound = @as(usize, @intCast(1)) <<
                @intCast(diluted_pool_instance.n_bits);

            // Check if unused diluted units are less than the upper bound
            if (unused_diluted_units < diluted_usage_upper_bound) {
                return MemoryError.InsufficientAllocatedCells;
            }
        }
    }

    /// Retrieves a pointer to the list of built-in functions defined in the program associated with the CairoRunner.
    ///
    /// This function returns a pointer to an ArrayList containing the names of the built-in functions defined in the program.
    ///
    /// # Arguments
    ///
    /// - `self`: A mutable reference to the CairoRunner instance.
    ///
    /// # Returns
    ///
    /// A pointer to an ArrayList containing the names of the built-in functions defined in the program.
    pub fn getProgramBuiltins(self: *Self) *ArrayList(BuiltinName) {
        return &self.program.builtins;
    }

    /// Retrieves the constant values used in the CairoRunner instance.
    ///
    /// This function returns a map containing the constant values used in the CairoRunner instance.
    /// The constants are represented as a `StringHashMap` where the keys are the names of the constants
    /// and the values are `Felt252` objects.
    ///
    /// # Arguments
    /// - `self`: A reference to the CairoRunner instance.
    ///
    /// # Returns
    /// A `StringHashMap` containing the constant values used in the CairoRunner instance.
    pub fn getConstants(self: *Self) std.StringHashMap(Felt252) {
        return self.program.constants;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        // currently handling the deinit of the json.Parsed(ProgramJson) outside of constructor
        // otherwise the runner would always assume json in its interface
        self.program.deinit(allocator);

        if (self.execution_public_memory) |execution_public_memory| execution_public_memory.deinit();

        self.instructions.deinit();
        self.layout.deinit();
        self.vm.deinit();
        self.relocated_memory.deinit();
        self.execution_scopes.deinit();
    }
};

test "CairoRunner: initMainEntrypoint no main" {
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    defer cairo_runner.deinit(std.testing.allocator);

    // Add an OutputBuiltinRunner to the CairoRunner without setting the stop pointer.
    try cairo_runner.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) });

    if (cairo_runner.initMainEntrypoint()) |_| {
        return error.ExpectedError;
    } else |_| {}
}

test "CairoRunner: initMainEntrypoint" {
    var program = try Program.initDefault(std.testing.allocator, true);

    program.shared_program_data.main = 1;

    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    defer cairo_runner.deinit(std.testing.allocator);
    // why this deinit is separated?
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    cairo_runner.program_base = Relocatable.init(0, 0);
    cairo_runner.execution_base = Relocatable.init(0, 0);

    // Add an OutputBuiltinRunner to the CairoRunner without setting the stop pointer.
    // try cairo_runner.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) });
    try expectEqual(
        Relocatable.init(1, 0),
        cairo_runner.initMainEntrypoint(),
    );
}

test "CairoRunner: initMainEntrypoint proof_mode empty program" {
    var program = try Program.initDefault(std.testing.allocator, true);

    program.shared_program_data.main = 8;
    program.shared_program_data.start = 0;
    program.shared_program_data.end = 0;

    var runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        true,
    );

    runner.runner_mode = .proof_mode_canonical;

    defer runner.deinit(std.testing.allocator);
    // why this deinit is separated?
    defer runner.vm.segments.memory.deinitData(std.testing.allocator);

    try runner.initSegments(null);

    try expectEqual(Relocatable.init(1, 0), runner.execution_base);
    try expectEqual(Relocatable.init(0, 0), runner.program_base);
    try expectEqual(Relocatable.init(0, 0), runner.initMainEntrypoint());
    try expectEqual(Relocatable.init(1, 2), runner.initial_ap);
    try expectEqual(runner.initial_fp, runner.initial_ap);
    try expectEqual([2]usize{ 0, 1 }, runner.execution_public_memory.?.items[0..2].*);
}

test "CairoRunner: initVM should initialize the VM properly with no builtins" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure proper cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set initial values for program_base, initial_pc, initial_ap, and initial_fp.
    cairo_runner.program_base = .{};
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
        cairo_runner.vm.run_context.getAP(),
    );
    // Expect that the frame pointer (FP) is initialized correctly.
    try expectEqual(
        Relocatable.init(1, 2),
        cairo_runner.vm.run_context.getFP(),
    );
}

test "CairoRunner: initVM should initialize the VM properly with Range Check builtin" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure proper cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

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
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure proper cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

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
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

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
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

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
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

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
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Ensure CairoRunner resources are cleaned up.
    defer cairo_runner.deinit(std.testing.allocator);

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
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

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
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Append an OutputBuiltinRunner to the CairoRunner's list of built-in runners.
    try cairo_runner.vm.builtin_runners.append(.{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) });

    // Initialize the segments for the CairoRunner with no provided base address (null).
    try cairo_runner.initSegments(null);

    // Expect that the program base is initialized correctly to (0, 0).
    try expectEqual(
        Relocatable{},
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

test "CairoRunner: getPermRangeCheckLimits with no builtin" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set up memory for the CairoRunner with a single memory cell.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{140739638165522} },
            .{ .{ 0, 1 }, .{211104085050912} },
            .{ .{ 0, 2 }, .{158327526917968} },
        },
    );

    // Create an ArrayList to hold the segment.
    var segment_1 = std.ArrayListUnmanaged(?MemoryCell){};

    // Append the MemoryCell to the segment N times.
    try segment_1.appendNTimes(
        std.testing.allocator,
        MemoryCell.init(MaybeRelocatable.fromSegment(0, 0)),
        128 * 1024,
    );

    // Append the segment to the memory data.
    try cairo_runner.vm.segments.memory.data.append(segment_1);

    // Defer the deinitialization of memory data to ensure cleanup.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Assign range limits to the CairoRunner instance.
    cairo_runner.vm.rc_limits = .{ 32768, 32803 };

    // Invoke the `getPermRangeCheckLimits` function and expect the result to match the expected tuple.
    try expectEqual(
        @as(?std.meta.Tuple(&.{ isize, isize }), .{ 32768, 32803 }),
        try cairo_runner.getPermRangeCheckLimits(std.testing.allocator),
    );
}

test "CairoRunner: getPermRangeCheckLimits with range check builtin" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set up memory for the CairoRunner with a single memory cell.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{141834852500784} }},
    );
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Add a range check builtin runner with specific parameters.
    try cairo_runner.vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(12, 5, true) });

    // Invoke the `getPermRangeCheckLimits` function and expect the result to match the expected tuple.
    try expectEqual(
        @as(?std.meta.Tuple(&.{ isize, isize }), .{ 0, 33023 }),
        try cairo_runner.getPermRangeCheckLimits(std.testing.allocator),
    );
}

test "CairoRunner: getPermRangeCheckLimits with null range limit" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Invoke the `getPermRangeCheckLimits` function and expect the result to be null.
    try expectEqual(
        null,
        try cairo_runner.getPermRangeCheckLimits(std.testing.allocator),
    );
}

test "CairoRunner: checkRangeCheckUsage perm range limits none" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    try cairo_runner.checkRangeCheckUsage(std.testing.allocator, &cairo_runner.vm);
}

test "CairoRunner: checkRangeCheckUsage without builtins" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    cairo_runner.vm.current_step = 10000;

    var segm = std.ArrayListUnmanaged(?MemoryCell){};
    try segm.append(std.testing.allocator, MemoryCell.init(MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 0x80FF80000530))));

    try cairo_runner.vm.segments.memory.data.append(segm);

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.checkRangeCheckUsage(std.testing.allocator, &cairo_runner.vm);
}
test "CairoRunner: get constants" {
    // Initialize a default program with built-ins enabled using the testing allocator.
    var program = try Program.initDefault(std.testing.allocator, true);

    // Add constants to the program.
    try program.constants.put("MAX", Felt252.fromInt(u64, 300));
    try program.constants.put("MIN", Felt252.fromInt(u64, 20));

    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions list.
    // Also initialize a CairoVM with an empty trace context.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner object to ensure cleanup after the test.
    defer cairo_runner.deinit(std.testing.allocator);

    // Retrieve the constants from the CairoRunner.
    const runner_program_constants = cairo_runner.getConstants();

    // Ensure that the count of constants retrieved matches the expected count (2).
    try expectEqual(@as(usize, 2), runner_program_constants.count());

    // Ensure that the constant value associated with the key "MAX" matches the expected value (300).
    try expectEqual(Felt252.fromInt(u64, 300), runner_program_constants.get("MAX"));

    // Ensure that the constant value associated with the key "MIN" matches the expected value (20).
    try expectEqual(Felt252.fromInt(u64, 20), runner_program_constants.get("MIN").?);
}

test "CairoRunner: initBuiltins missing builtins allow missing" {
    var program = try Program.initDefault(std.testing.allocator, true);
    try program.builtins.appendSlice(&.{ .output, .ecdsa });
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
}

test "CairoRunner: initBuiltins missing builtins no allow missing" {
    var program = try Program.initDefault(std.testing.allocator, true);
    try program.builtins.appendSlice(&.{ .output, .ecdsa });
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    try std.testing.expectError(RunnerError.NoBuiltinForInstance, cairo_runner.initBuiltins(false));
}

test "CairoRunner: initBuiltins with disordered builtins" {
    var program = try Program.initDefault(std.testing.allocator, true);
    try program.builtins.appendSlice(&.{ .range_check, .output });
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    try std.testing.expectError(RunnerError.DisorderedBuiltins, cairo_runner.initBuiltins(false));
}

test "CairoRunner: initBuiltins all builtins and maintain order" {
    var program = try Program.initDefault(std.testing.allocator, true);
    try program.builtins.appendSlice(&.{
        .output,
        .pedersen,
        .range_check,
        .ecdsa,
        .bitwise,
        .ec_op,
        .keccak,
        .poseidon,
    });
    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    try cairo_runner.initBuiltins(false);

    const given_runners = cairo_runner.vm.getBuiltinRunners().items;

    try std.testing.expectEqual(given_runners[0].name(), builtin_runner_import.OUTPUT_BUILTIN_NAME);
    try std.testing.expectEqual(given_runners[1].name(), builtin_runner_import.HASH_BUILTIN_NAME);
    try std.testing.expectEqual(given_runners[2].name(), builtin_runner_import.RANGE_CHECK_BUILTIN_NAME);
    try std.testing.expectEqual(given_runners[3].name(), builtin_runner_import.SIGNATURE_BUILTIN_NAME);
    try std.testing.expectEqual(given_runners[4].name(), builtin_runner_import.BITWISE_BUILTIN_NAME);
    try std.testing.expectEqual(given_runners[5].name(), builtin_runner_import.EC_OP_BUILTIN_NAME);
    try std.testing.expectEqual(given_runners[6].name(), builtin_runner_import.KECCAK_BUILTIN_NAME);
    try std.testing.expectEqual(given_runners[7].name(), builtin_runner_import.POSEIDON_BUILTIN_NAME);
}

test "CairoRunner: initial FP should be null if no initialization" {
    // Initialize a CairoRunner instance with default parameters for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Verify that the initial function pointer (FP) is null.
    try expectEqual(null, cairo_runner.initial_fp);
}

test "CairoRunner: initial FP with a simple program" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner instance with the created Program and CairoVM instances.

    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set the program and execution base addresses.
    cairo_runner.program_base = .{};
    cairo_runner.execution_base = Relocatable.init(1, 0);

    // Initialize a stack for function entrypoint testing.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit();
    _ = try cairo_runner.initFunctionEntrypoint(0, MaybeRelocatable.fromInt(u8, 9), &stack);

    // Deinitialize memory segments.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Verify that the initial function pointer (FP) is correct.
    try expectEqual(Relocatable.init(1, 2), cairo_runner.initial_fp);
}

test "CairoRunner: getMemoryHoles with missing segment used sizes" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set up memory for the Cairo VM with missing segment used sizes.
    // Allocator for memory allocation
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{9} }},
    );
    // Defer memory cleanup
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Mark the memory as accessed (placeholder operation)
    cairo_runner.vm.segments.memory.markAsAccessed(.{});

    // Test that invoking `getMemoryHoles` function throws the expected error.
    try expectError(MemoryError.MissingSegmentUsedSizes, cairo_runner.getMemoryHoles());
}

test "CairoRunner: getMemoryHoles empty" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Test that invoking `getMemoryHoles` function returns 0 when there are no memory holes.
    try expectEqual(@as(usize, 0), try cairo_runner.getMemoryHoles());
}

test "CairoRunner: getMemoryHoles with segment used size" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    // Allocator for memory allocation
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set up memory for the Cairo VM with specified segment used sizes.
    // Allocator for memory allocation
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0} },
            .{ .{ 0, 2 }, .{0} },
        },
    );
    // Defer memory cleanup
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Specify segment used size for segment 0
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);

    // Mark the specified memory cells as accessed (placeholder operation)
    cairo_runner.vm.segments.memory.markAsAccessed(.{});
    cairo_runner.vm.segments.memory.markAsAccessed(Relocatable.init(0, 2));

    // Test that invoking `getMemoryHoles` function returns the expected number of memory holes.
    try expectEqual(@as(usize, 2), try cairo_runner.getMemoryHoles());
}

test "CairoRunner: getMemoryHoles with empty accesses" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    // Allocator for memory allocation
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set up memory for the Cairo VM with specified memory cell accesses.
    // Allocator for memory allocation
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{0} },
            .{ .{ 1, 2 }, .{2} },
        },
    );
    // Defer memory cleanup
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Mark specified memory cells as accessed in segment 1
    cairo_runner.vm.segments.memory.markAsAccessed(Relocatable.init(1, 0));
    cairo_runner.vm.segments.memory.markAsAccessed(Relocatable.init(1, 2));

    // Initialize an OutputBuiltinRunner for testing
    var output_builtin: BuiltinRunner = .{
        .Output = OutputBuiltinRunner.init(std.testing.allocator, true),
    };

    // Initialize segments for the OutputBuiltinRunner
    try output_builtin.initSegments(cairo_runner.vm.segments);

    // Append the OutputBuiltinRunner to the list of builtin runners in Cairo VM
    try cairo_runner.vm.builtin_runners.append(output_builtin);

    // Specify segment used sizes for both segments
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);
    try cairo_runner.vm.segments.segment_used_sizes.put(1, 4);

    // Test that invoking `getMemoryHoles` function returns the expected number of memory holes.
    try expectEqual(@as(usize, 2), try cairo_runner.getMemoryHoles());
}

test "CairoRunner: getMemoryHoles basic test" {
    // Initialize a CairoRunner with an empty program, "plain" layout, and empty instructions.
    // Allocator for memory allocation
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Initialize an OutputBuiltinRunner for testing
    var output_builtin: BuiltinRunner = .{
        .Output = OutputBuiltinRunner.init(std.testing.allocator, true),
    };

    // Initialize segments for the OutputBuiltinRunner
    try output_builtin.initSegments(cairo_runner.vm.segments);

    // Append the OutputBuiltinRunner to the list of builtin runners in Cairo VM
    try cairo_runner.vm.builtin_runners.append(output_builtin);

    // Specify segment used sizes for segment 0
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);

    // Test that invoking `getMemoryHoles` function returns 0 as there are no memory holes.
    try expectEqual(@as(usize, 0), try cairo_runner.getMemoryHoles());
}

test "CairoRunner: getProgramBuiltins" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);
    try builtins.append(BuiltinName.ec_op);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoRunner instance with the initialized Program.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(std.testing.allocator, .{}),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Call the `getProgramBuiltins` function to retrieve the list of built-in functions.
    // Verify that the retrieved list matches the expected list of built-in functions.
    try expectEqualSlices(
        BuiltinName,
        &[_]BuiltinName{ .output, .ec_op },
        cairo_runner.getProgramBuiltins().items,
    );
}

test "CairoRunner: initState with empty data and stack" {
    // Initialize a list of built-ins.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set program_base and execution_base fields of cairo_runner.
    cairo_runner.program_base = Relocatable.init(1, 0);
    cairo_runner.execution_base = Relocatable.init(2, 0);

    // Initialize a stack.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit();

    // Call initState function to initialize the runner state.
    try cairo_runner.initState(1, &stack);

    // Assert that the initial_pc field is correctly set.
    try expectEqual(Relocatable.init(1, 1), cairo_runner.initial_pc);
}

test "CairoRunner: initState with some data and empty stack" {
    // Initialize a list of built-ins.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data array with some values.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u8, 4)); // Add integer value 4 to data array.
    try data.append(MaybeRelocatable.fromInt(u8, 6)); // Add integer value 6 to data array.

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set program base and execution base.
    cairo_runner.program_base = Relocatable.init(1, 0);
    cairo_runner.execution_base = Relocatable.init(2, 0);

    // Initialize an empty stack.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit();

    // Initialize the runner state.
    try cairo_runner.initState(1, &stack);

    // Deinitialize memory segments.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Verify that the correct values were loaded into memory and accessed.
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 4),
        cairo_runner.vm.segments.memory.get(Relocatable.init(1, 0)).?,
    );
    try expect(cairo_runner.vm.segments.memory.data.items[1].items[0].?.is_accessed);
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 6),
        cairo_runner.vm.segments.memory.get(Relocatable.init(1, 1)).?,
    );
    try expect(cairo_runner.vm.segments.memory.data.items[1].items[1].?.is_accessed);
}

test "CairoRunner: initState with empty data and some stack" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator); // Initialize empty data.

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..3) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set program base and execution base.
    cairo_runner.program_base = Relocatable.init(1, 0);
    cairo_runner.execution_base = Relocatable.init(2, 0);

    // Initialize a stack with some values.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit(); // Deallocate stack memory after the test.
    try stack.append(MaybeRelocatable.fromInt(u8, 4)); // Add integer value 4 to the stack.
    try stack.append(MaybeRelocatable.fromInt(u8, 6)); // Add integer value 6 to the stack.

    // Initialize the runner state.
    try cairo_runner.initState(1, &stack);

    // Deinitialize memory segments.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Verify that the correct values were loaded into memory and not accessed.
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 4),
        cairo_runner.vm.segments.memory.get(Relocatable.init(2, 0)).?,
    );
    try expect(!cairo_runner.vm.segments.memory.data.items[2].items[0].?.is_accessed);
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 6),
        cairo_runner.vm.segments.memory.get(Relocatable.init(2, 1)).?,
    );
    try expect(!cairo_runner.vm.segments.memory.data.items[2].items[1].?.is_accessed);
}

test "CairoRunner: initState with no program_base" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set only execution base without program base.
    cairo_runner.execution_base = Relocatable.init(2, 0);

    // Initialize a stack with some values.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit(); // Deallocate stack memory after the test.
    try stack.append(MaybeRelocatable.fromInt(u8, 4)); // Add integer value 4 to the stack.
    try stack.append(MaybeRelocatable.fromInt(u8, 6)); // Add integer value 6 to the stack.

    // Expect an error when trying to initialize the runner state without a program base.
    try expectError(RunnerError.MemoryInitializationError, cairo_runner.initState(1, &stack));
}

test "CairoRunner: initState with no execution_base" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set only program base without execution base.
    cairo_runner.program_base = Relocatable.init(1, 0);

    // Initialize a stack with some values.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit(); // Deallocate stack memory after the test.
    try stack.append(MaybeRelocatable.fromInt(u8, 4)); // Add integer value 4 to the stack.
    try stack.append(MaybeRelocatable.fromInt(u8, 6)); // Add integer value 6 to the stack.

    // Expect an error when trying to initialize the runner state without an execution base.
    // try expectError(RunnerError.NoProgBase, cairo_runner.initState(1, &stack));
}

test "CairoRunner: initFunctionEntrypoint with empty stack" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set only program base and execution base.
    cairo_runner.program_base = Relocatable.init(0, 0);
    cairo_runner.execution_base = Relocatable.init(1, 0);

    // Initialize a stack with some values.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit(); // Deallocate stack memory after the test.

    const return_fp = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 9));

    _ = try cairo_runner.initFunctionEntrypoint(0, return_fp, &stack);

    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try expect(cairo_runner.initial_fp.?.eq(cairo_runner.initial_ap.?));

    try expect(cairo_runner.initial_ap.?.eq(Relocatable.init(1, 2)));

    const memory = vm.segments.memory;

    var cells = std.ArrayList(TestingUtils.Cell).init(std.testing.allocator);
    defer cells.deinit();

    try cells.append(.{ .address = Relocatable.init(1, 0), .value = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 9)) });
    try cells.append(.{ .address = Relocatable.init(1, 1), .value = MaybeRelocatable.fromRelocatable(Relocatable.init(2, 0)) });

    try expect(TestingUtils.check_memory(memory, cells));
}

test "CairoRunner: initFunctionEntrypoint with some stack" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set only program base and execution base.
    cairo_runner.program_base = Relocatable.init(0, 0);
    cairo_runner.execution_base = Relocatable.init(1, 0);

    // Initialize a stack with some values.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit(); // Deallocate stack memory after the test.

    try stack.append(MaybeRelocatable.fromInt(u8, 7));

    const return_fp = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 9));

    _ = try cairo_runner.initFunctionEntrypoint(1, return_fp, &stack);

    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try expect(cairo_runner.initial_fp.?.eq(cairo_runner.initial_ap.?));

    try expect(cairo_runner.initial_ap.?.eq(Relocatable.init(1, 3)));

    const memory = vm.segments.memory;

    var cells = std.ArrayList(TestingUtils.Cell).init(std.testing.allocator);
    defer cells.deinit();

    try cells.append(.{ .address = Relocatable.init(1, 0), .value = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 7)) });
    try cells.append(.{ .address = Relocatable.init(1, 1), .value = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 9)) });
    try cells.append(.{ .address = Relocatable.init(1, 2), .value = MaybeRelocatable.fromRelocatable(Relocatable.init(2, 0)) });

    try expect(TestingUtils.check_memory(memory, cells));
}

test "CairoRunner: initFunctionEntrypoint with no execution base" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Add memory segments to the CairoVM instance.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    // Set only program base and execution base.
    cairo_runner.program_base = Relocatable.init(1, 0);

    // Initialize a stack with some values.
    var stack = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer stack.deinit(); // Deallocate stack memory after the test.

    try stack.append(MaybeRelocatable.fromInt(u8, 7));

    const return_fp = MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 9));

    // Expect an error when trying to initialize the runner state without an execution base.
    try expectError(RunnerError.NoExecBase, cairo_runner.initFunctionEntrypoint(1, return_fp, &stack));

    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);
}

test "CairoRunner: runUntilPC with function call" {

    //Program used:
    //func myfunc(a: felt) -> (r: felt):
    //    let b = a * 2
    //    return(b)
    //end
    //
    //func main():
    //    let a = 1
    //    let b = myfunc(a)
    //    return()
    //end
    //
    //main = 3
    //data = [5207990763031199744, 2, 2345108766317314046, 5189976364521848832, 1,
    //1226245742482522112, 3618502788666131213697322783095070105623107215331596699973092056135872020476,
    //2345108766317314046]

    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u64, 5207990763031199744));
    try data.append(MaybeRelocatable.fromInt(u64, 2));
    try data.append(MaybeRelocatable.fromInt(u64, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u64, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u64, 1));
    try data.append(MaybeRelocatable.fromInt(u64, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020476));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        3,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    var hint_processor: HintProcessor = .{};

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(3, 0), end);

    try cairo_runner.initVM();

    try cairo_runner.runUntilPC(end, false, &hint_processor);

    try expectEqual(Relocatable.init(3, 0), cairo_runner.vm.run_context.pc.*);
    try expectEqual(
        Relocatable.init(1, 6),
        cairo_runner.vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        cairo_runner.vm.run_context.getFP(),
    );

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(0, 3),
                .ap = Relocatable.init(1, 2),
                .fp = Relocatable.init(1, 2),
            },
            .{
                .pc = Relocatable.init(0, 5),
                .ap = Relocatable.init(1, 3),
                .fp = Relocatable.init(1, 2),
            },
            .{
                .pc = Relocatable.init(0, 0),
                .ap = Relocatable.init(1, 5),
                .fp = Relocatable.init(1, 5),
            },
            .{
                .pc = Relocatable.init(0, 2),
                .ap = Relocatable.init(1, 6),
                .fp = Relocatable.init(1, 5),
            },
            .{
                .pc = Relocatable.init(0, 7),
                .ap = Relocatable.init(1, 6),
                .fp = Relocatable.init(1, 2),
            },
        },
        cairo_runner.vm.trace.?.items,
    );
}

test "CairoRunner: runUntilPC with range check builtin" {

    //Program used:
    //%builtins range_check
    //
    //func check_range{range_check_ptr}(num):

    //    # Check that 0 <= num < 2**64.
    //    [range_check_ptr] = num
    //    assert [range_check_ptr + 1] = 2 ** 64 - 1 - num
    //    let range_check_ptr = range_check_ptr + 2
    //    return()
    // end
    //
    //func main{range_check_ptr}():
    //    check_range(7)
    //    return()
    //end
    //
    //main = 8
    //data = [4612671182993129469, 5189976364521848832, 18446744073709551615,
    // 5199546496550207487, 4612389712311386111, 5198983563776393216, 2,
    // 2345108766317314046, 5191102247248822272, 5189976364521848832, 7,
    // 1226245742482522112,
    // 3618502788666131213697322783095070105623107215331596699973092056135872020470,
    // 2345108766317314046]

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.range_check);

    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u64, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u64, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u64, 18446744073709551615));
    try data.append(MaybeRelocatable.fromInt(u64, 5199546496550207487));
    try data.append(MaybeRelocatable.fromInt(u64, 4612389712311386111));
    try data.append(MaybeRelocatable.fromInt(u64, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 2));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 7));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        8,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    try expectEqual(Relocatable.init(4, 0), cairo_runner.vm.run_context.pc.*);
    try expectEqual(
        Relocatable.init(1, 10),
        cairo_runner.vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        cairo_runner.vm.run_context.getFP(),
    );

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(0, 8),
                .ap = Relocatable.init(1, 3),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 9),
                .ap = Relocatable.init(1, 4),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 11),
                .ap = Relocatable.init(1, 5),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 0),
                .ap = Relocatable.init(1, 7),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 1),
                .ap = Relocatable.init(1, 7),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 3),
                .ap = Relocatable.init(1, 8),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 4),
                .ap = Relocatable.init(1, 9),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 5),
                .ap = Relocatable.init(1, 9),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 7),
                .ap = Relocatable.init(1, 10),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 13),
                .ap = Relocatable.init(1, 10),
                .fp = Relocatable.init(1, 3),
            },
        },
        cairo_runner.vm.trace.?.items,
    );

    try expectEqual(
        builtin_runner_import.RANGE_CHECK_BUILTIN_NAME,
        cairo_runner.vm.builtin_runners.items[0].name(),
    );
    try expectEqual(
        @as(usize, 2),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 7),
        cairo_runner.vm.segments.memory.data.items[2].items[0].?.maybe_relocatable,
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u256, 18446744073709551608),
        cairo_runner.vm.segments.memory.data.items[2].items[1].?.maybe_relocatable,
    );

    try expectEqual(
        null,
        cairo_runner.vm.segments.memory.get(Relocatable.init(2, 2)),
    );
}

test "CairoRunner: initialize and run with output builtin" {
    //Program used:
    //%builtins output
    //
    //from starkware.cairo.common.serialize import serialize_word
    //
    //func main{output_ptr: felt*}():
    //    let a = 1
    //    serialize_word(a)
    //    let b = 17 * a
    //    serialize_word(b)
    //    return()
    //end
    //
    //main = 4
    //data = [
    //4612671182993129469,
    //5198983563776393216,
    //1,
    //2345108766317314046,
    //5191102247248822272,
    //5189976364521848832,
    //1,
    //1226245742482522112,
    //3618502788666131213697322783095070105623107215331596699973092056135872020474,
    //5189976364521848832,
    //17,
    //1226245742482522112,
    //3618502788666131213697322783095070105623107215331596699973092056135872020470,
    //2345108766317314046
    //]

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020474));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 17));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        4,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    try expectEqual(Relocatable.init(4, 0), cairo_runner.vm.run_context.pc.*);
    try expectEqual(
        Relocatable.init(1, 12),
        cairo_runner.vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        cairo_runner.vm.run_context.getFP(),
    );

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(0, 4),
                .ap = Relocatable.init(1, 3),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 5),
                .ap = Relocatable.init(1, 4),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 7),
                .ap = Relocatable.init(1, 5),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 0),
                .ap = Relocatable.init(1, 7),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 1),
                .ap = Relocatable.init(1, 7),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 3),
                .ap = Relocatable.init(1, 8),
                .fp = Relocatable.init(1, 7),
            },
            .{
                .pc = Relocatable.init(0, 9),
                .ap = Relocatable.init(1, 8),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 11),
                .ap = Relocatable.init(1, 9),
                .fp = Relocatable.init(1, 3),
            },
            .{
                .pc = Relocatable.init(0, 0),
                .ap = Relocatable.init(1, 11),
                .fp = Relocatable.init(1, 11),
            },
            .{
                .pc = Relocatable.init(0, 1),
                .ap = Relocatable.init(1, 11),
                .fp = Relocatable.init(1, 11),
            },
            .{
                .pc = Relocatable.init(0, 3),
                .ap = Relocatable.init(1, 12),
                .fp = Relocatable.init(1, 11),
            },
            .{
                .pc = Relocatable.init(0, 13),
                .ap = Relocatable.init(1, 12),
                .fp = Relocatable.init(1, 3),
            },
        },
        cairo_runner.vm.trace.?.items,
    );

    try expectEqual(
        builtin_runner_import.OUTPUT_BUILTIN_NAME,
        cairo_runner.vm.builtin_runners.items[0].name(),
    );
    try expectEqual(
        @as(usize, 2),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 1),
        cairo_runner.vm.segments.memory.data.items[2].items[0].?.maybe_relocatable,
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u256, 17),
        cairo_runner.vm.segments.memory.data.items[2].items[1].?.maybe_relocatable,
    );

    try expectEqual(
        null,
        cairo_runner.vm.segments.memory.get(Relocatable.init(2, 2)),
    );
}

test "CairoRunner: initialize and run with range check and output builtins" {
    //Program used:
    //%builtins output range_check
    //
    //from starkware.cairo.common.serialize import serialize_word
    //
    //func check_range{range_check_ptr}(num) -> (num : felt):
    //
    //# Check that 0 <= num < 2**64.
    //[range_check_ptr] = num
    //assert [range_check_ptr + 1] = 2 ** 64 - 1 - num
    //let range_check_ptr = range_check_ptr + 2
    //return(num)
    //end
    //
    //func main{output_ptr: felt*, range_check_ptr: felt}():
    //let num: felt = check_range(7)
    //serialize_word(num)
    //return()
    //end
    //
    //main = 13
    //data = [
    //4612671182993129469,
    //5198983563776393216,
    //1,
    //2345108766317314046,
    //4612671182993129469,
    //5189976364521848832,
    //18446744073709551615,
    //5199546496550207487,
    //4612389712311386111,
    //5198983563776393216,
    //2,
    //5191102247248822272,
    //2345108766317314046,
    //5191102247248822272,
    //5189976364521848832,
    //7,
    //1226245742482522112,
    //3618502788666131213697322783095070105623107215331596699973092056135872020469,
    //5191102242953854976,
    //5193354051357474816,
    //1226245742482522112,
    //3618502788666131213697322783095070105623107215331596699973092056135872020461,
    //5193354029882638336,
    //2345108766317314046]

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);
    try builtins.append(BuiltinName.range_check);

    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 18446744073709551615));
    try data.append(MaybeRelocatable.fromInt(u256, 5199546496550207487));
    try data.append(MaybeRelocatable.fromInt(u256, 4612389712311386111));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 2));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 7));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020469));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102242953854976));
    try data.append(MaybeRelocatable.fromInt(u256, 5193354051357474816));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020461));
    try data.append(MaybeRelocatable.fromInt(u256, 5193354029882638336));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        13,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(5, 0), end);

    try cairo_runner.initVM();

    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    try expectEqual(Relocatable.init(5, 0), cairo_runner.vm.run_context.pc.*);
    try expectEqual(
        Relocatable.init(1, 18),
        cairo_runner.vm.run_context.getAP(),
    );
    try expectEqual(
        Relocatable.init(1, 0),
        cairo_runner.vm.run_context.getFP(),
    );

    try expectEqualSlices(
        TraceEntry,
        &[_]TraceEntry{
            .{
                .pc = Relocatable.init(0, 13),
                .ap = Relocatable.init(1, 4),
                .fp = Relocatable.init(1, 4),
            },
            .{
                .pc = Relocatable.init(0, 14),
                .ap = Relocatable.init(1, 5),
                .fp = Relocatable.init(1, 4),
            },
            .{
                .pc = Relocatable.init(0, 16),
                .ap = Relocatable.init(1, 6),
                .fp = Relocatable.init(1, 4),
            },
            .{
                .pc = Relocatable.init(0, 4),
                .ap = Relocatable.init(1, 8),
                .fp = Relocatable.init(1, 8),
            },
            .{
                .pc = Relocatable.init(0, 5),
                .ap = Relocatable.init(1, 8),
                .fp = Relocatable.init(1, 8),
            },
            .{
                .pc = Relocatable.init(0, 7),
                .ap = Relocatable.init(1, 9),
                .fp = Relocatable.init(1, 8),
            },
            .{
                .pc = Relocatable.init(0, 8),
                .ap = Relocatable.init(1, 10),
                .fp = Relocatable.init(1, 8),
            },
            .{
                .pc = Relocatable.init(0, 9),
                .ap = Relocatable.init(1, 10),
                .fp = Relocatable.init(1, 8),
            },
            .{
                .pc = Relocatable.init(0, 11),
                .ap = Relocatable.init(1, 11),
                .fp = Relocatable.init(1, 8),
            },
            .{
                .pc = Relocatable.init(0, 12),
                .ap = Relocatable.init(1, 12),
                .fp = Relocatable.init(1, 8),
            },
            .{
                .pc = Relocatable.init(0, 18),
                .ap = Relocatable.init(1, 12),
                .fp = Relocatable.init(1, 4),
            },
            .{
                .pc = Relocatable.init(0, 19),
                .ap = Relocatable.init(1, 13),
                .fp = Relocatable.init(1, 4),
            },
            .{
                .pc = Relocatable.init(0, 20),
                .ap = Relocatable.init(1, 14),
                .fp = Relocatable.init(1, 4),
            },
            .{
                .pc = Relocatable.init(0, 0),
                .ap = Relocatable.init(1, 16),
                .fp = Relocatable.init(1, 16),
            },
            .{
                .pc = Relocatable.init(0, 1),
                .ap = Relocatable.init(1, 16),
                .fp = Relocatable.init(1, 16),
            },
            .{
                .pc = Relocatable.init(0, 3),
                .ap = Relocatable.init(1, 17),
                .fp = Relocatable.init(1, 16),
            },
            .{
                .pc = Relocatable.init(0, 22),
                .ap = Relocatable.init(1, 17),
                .fp = Relocatable.init(1, 4),
            },
            .{
                .pc = Relocatable.init(0, 23),
                .ap = Relocatable.init(1, 18),
                .fp = Relocatable.init(1, 4),
            },
        },
        cairo_runner.vm.trace.?.items,
    );

    try expectEqual(
        builtin_runner_import.RANGE_CHECK_BUILTIN_NAME,
        cairo_runner.vm.builtin_runners.items[1].name(),
    );
    try expectEqual(
        @as(usize, 3),
        cairo_runner.vm.builtin_runners.items[1].base(),
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 7),
        cairo_runner.vm.segments.memory.data.items[3].items[0].?.maybe_relocatable,
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u256, 18446744073709551608),
        cairo_runner.vm.segments.memory.data.items[3].items[1].?.maybe_relocatable,
    );
    try expectEqual(
        null,
        cairo_runner.vm.segments.memory.get(Relocatable.init(2, 2)),
    );

    try expectEqual(
        builtin_runner_import.OUTPUT_BUILTIN_NAME,
        cairo_runner.vm.builtin_runners.items[0].name(),
    );
    try expectEqual(
        @as(usize, 2),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 7),
        cairo_runner.vm.segments.memory.data.items[2].items[0].?.maybe_relocatable,
    );
    try expectEqual(
        null,
        cairo_runner.vm.segments.memory.get(Relocatable.init(2, 1)),
    );
}

test "CairoRunner: initialize and run relocate with output builtin" {

    //Program used:
    //%builtins output
    //
    //from starkware.cairo.common.serialize import serialize_word
    //
    //func main{output_ptr: felt*}():
    //  let a = 1
    //  serialize_word(a)
    //  let b = 17 * a
    //  serialize_word(b)
    //  return()
    //end
    //Relocated Memory:
    //    1     4612671182993129469
    //    2     5198983563776393216
    //    3     1
    //    4     2345108766317314046
    //    5     5191102247248822272
    //    6     5189976364521848832
    //    7     1
    //    8     1226245742482522112
    //    9     -7
    //    10    5189976364521848832
    //    11    17
    //    12    1226245742482522112
    //    13    -11
    //    14    2345108766317314046
    //    15    27
    //    16    29
    //    17    29
    //    18    27
    //    19    1
    //    20    18
    //    21    10
    //    22    28
    //    23    17
    //    24    18
    //    25    14
    //    26    29
    //    27    1
    //    28    17

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020474));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 17));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        4,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    _ = try cairo_runner.vm.computeSegmentsEffectiveSizes(false);

    const relocation_table = try cairo_runner.vm.segments.relocateSegments(std.testing.allocator);
    defer std.testing.allocator.free(relocation_table);

    try cairo_runner.relocateMemory(relocation_table);

    // Perform assertions to check if memory relocation is correct.
    try expectEqualSlices(
        ?Felt252,
        &[_]?Felt252{
            null,
            Felt252.fromInt(u256, 4612671182993129469),
            Felt252.fromInt(u256, 5198983563776393216),
            Felt252.fromInt(u256, 1),
            Felt252.fromInt(u256, 2345108766317314046),
            Felt252.fromInt(u256, 5191102247248822272),
            Felt252.fromInt(u256, 5189976364521848832),
            Felt252.fromInt(u256, 1),
            Felt252.fromInt(u256, 1226245742482522112),
            Felt252.fromInt(u256, 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffffa),
            Felt252.fromInt(u256, 5189976364521848832),
            Felt252.fromInt(u256, 17),
            Felt252.fromInt(u256, 1226245742482522112),
            Felt252.fromInt(u256, 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffff6),
            Felt252.fromInt(u256, 2345108766317314046),
            Felt252.fromInt(u256, 27),
            Felt252.fromInt(u256, 29),
            Felt252.fromInt(u256, 29),
            Felt252.fromInt(u256, 27),
            Felt252.fromInt(u256, 1),
            Felt252.fromInt(u256, 18),
            Felt252.fromInt(u256, 10),
            Felt252.fromInt(u256, 28),
            Felt252.fromInt(u256, 17),
            Felt252.fromInt(u256, 18),
            Felt252.fromInt(u256, 14),
            Felt252.fromInt(u256, 29),
            Felt252.fromInt(u256, 1),
            Felt252.fromInt(u256, 17),
        },
        cairo_runner.relocated_memory.items,
    );
}

test "CairoRunner: initialize and run relocate trace with output builtin" {

    //Program used:
    //%builtins output
    //
    //from starkware.cairo.common.serialize import serialize_word
    //
    //func main{output_ptr: felt*}():
    //    let a = 1
    //    serialize_word(a)
    //    let b = 17 * a
    //    serialize_word(b)
    //    return()
    //end
    //
    //Relocated Trace:
    //[TraceEntry(pc=5, ap=18, fp=18),
    //    TraceEntry(pc=6, ap=19, fp=18),
    //    TraceEntry(pc=8, ap=20, fp=18),
    //    TraceEntry(pc=1, ap=22, fp=22),
    //    TraceEntry(pc=2, ap=22, fp=22),
    //    TraceEntry(pc=4, ap=23, fp=22),
    //    TraceEntry(pc=10, ap=23, fp=18),

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020474));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 17));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        4,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    try cairo_runner.relocate();

    // Perform assertions to check if memory relocation is correct.
    try expectEqualSlices(
        RelocatedTraceEntry,
        &[_]RelocatedTraceEntry{
            .{
                .pc = 5,
                .ap = 18,
                .fp = 18,
            },
            .{
                .pc = 6,
                .ap = 19,
                .fp = 18,
            },
            .{
                .pc = 8,
                .ap = 20,
                .fp = 18,
            },
            .{
                .pc = 1,
                .ap = 22,
                .fp = 22,
            },
            .{
                .pc = 2,
                .ap = 22,
                .fp = 22,
            },
            .{
                .pc = 4,
                .ap = 23,
                .fp = 22,
            },
            .{
                .pc = 10,
                .ap = 23,
                .fp = 18,
            },
            .{
                .pc = 12,
                .ap = 24,
                .fp = 18,
            },
            .{
                .pc = 1,
                .ap = 26,
                .fp = 26,
            },
            .{
                .pc = 2,
                .ap = 26,
                .fp = 26,
            },
            .{
                .pc = 4,
                .ap = 27,
                .fp = 26,
            },
            .{
                .pc = 14,
                .ap = 27,
                .fp = 18,
            },
        },
        cairo_runner.relocated_trace.?,
    );
}

test "CairoRunner: write output from preset memory" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(std.testing.allocator, .{});

    // Initialize a CairoRunner instance with the created Program and CairoVM instances.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    try cairo_runner.initBuiltins(false);
    try cairo_runner.initSegments(null);

    // Assert the name and base of the output builtin runner.
    try expectEqual(
        builtin_runner_import.OUTPUT_BUILTIN_NAME,
        cairo_runner.vm.builtin_runners.items[0].name(),
    );
    try expectEqual(
        @as(usize, 2),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );

    // Set up memory with preset data.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 2, 0 }, .{1} },
            .{ .{ 2, 1 }, .{2} },
        },
    );
    // Defer memory cleanup
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Initialize segment used sizes.
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 0);
    try cairo_runner.vm.segments.segment_used_sizes.put(1, 0);
    try cairo_runner.vm.segments.segment_used_sizes.put(2, 2);

    // Initialize output buffer.
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    // Write output to the output buffer.
    try cairo_runner.vm.writeOutput(output.writer());

    // Assert the output buffer content.
    try expectEqualSlices(u8, "1\n2\n", output.items);
}

test "CairoRunner: get output from a program" {

    //Program used:
    //%builtins output
    //
    //from starkware.cairo.common.serialize import serialize_word
    //
    //func main{output_ptr: felt*}():
    //    let a = 1
    //    serialize_word(a)
    //    return()
    //end

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data with preset values.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020474));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 17));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        4,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    // Run the program.
    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    // Initialize output buffer.
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    // Write output to the output buffer.
    try cairo_runner.vm.writeOutput(output.writer());

    // Assert the output buffer content.
    try expectEqualSlices(u8, "1\n17\n", output.items);
}

test "CairoRunner: write output from a program with gap and relocatable output" {

    //Program used:
    //%builtins output
    //
    //func main{output_ptr: felt*}() {
    //    //Memory Gap + Relocatable value
    //    assert [output_ptr + 1] = cast(output_ptr, felt);
    //    let output_ptr = output_ptr + 2;
    //    return ();
    //}

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data with preset values.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671187288162301));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776458752));
    try data.append(MaybeRelocatable.fromInt(u256, 2));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        0,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    // Run the program.
    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    // Initialize output buffer.
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    // Write output to the output buffer.
    try cairo_runner.vm.writeOutput(output.writer());

    // Assert the output buffer content.
    try expectEqualSlices(u8, "<missing>\n2:0\n", output.items);
}

test "CairoRunner: write output from preset memory with negative output" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(std.testing.allocator, .{});

    // Initialize a CairoRunner instance with the created Program and CairoVM instances.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    try cairo_runner.initBuiltins(false);
    try cairo_runner.initSegments(null);

    // Assert the name and base of the output builtin runner.
    try expectEqual(
        builtin_runner_import.OUTPUT_BUILTIN_NAME,
        cairo_runner.vm.builtin_runners.items[0].name(),
    );
    try expectEqual(
        @as(usize, 2),
        cairo_runner.vm.builtin_runners.items[0].base(),
    );

    // Set up memory with preset data.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 2, 0 }, .{0x800000000000011000000000000000000000000000000000000000000000000} },
        },
    );
    // Defer memory cleanup
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Initialize segment used sizes.
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 0);
    try cairo_runner.vm.segments.segment_used_sizes.put(1, 0);
    try cairo_runner.vm.segments.segment_used_sizes.put(2, 1);

    // Initialize output buffer.
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    // Write output to the output buffer.
    try cairo_runner.vm.writeOutput(output.writer());

    // Assert the output buffer content.
    try expectEqualSlices(u8, "-1\n", output.items);
}

test "CairoRunner: get output with unordered builtins" {

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.output);
    try builtins.append(BuiltinName.bitwise);

    // Initialize data with preset values.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020474));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 17));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        4,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);

    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);

    // Exchange builtins order to make them unordered
    try cairo_runner.vm.builtin_runners.append(cairo_runner.vm.builtin_runners.swapRemove(0));

    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(5, 0), end);

    try cairo_runner.initVM();

    // Run the program.
    var hint_processor: HintProcessor = .{};
    try cairo_runner.runUntilPC(end, false, &hint_processor);

    // Initialize output buffer.
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    // Write output to the output buffer.
    try cairo_runner.vm.writeOutput(output.writer());

    // Assert the output buffer content.
    try expectEqualSlices(u8, "1\n17\n", output.items);
}

test "CairoRunner: run for steps" {

    //Program used:
    //%builtins range_check
    //
    //func check_range{range_check_ptr}(num):
    //    # Check that 0 <= num < 2**64.
    //    [range_check_ptr] = num
    //    assert [range_check_ptr + 1] = 2 ** 64 - 1 - num
    //    let range_check_ptr = range_check_ptr + 2
    //    return()
    //end
    //
    //func main{range_check_ptr}():
    //    check_range(7)
    //    return()
    //end
    //
    //main = 8
    //data = [4612671182993129469, 5189976364521848832, 18446744073709551615,
    //5199546496550207487, 4612389712311386111, 5198983563776393216,
    //2, 2345108766317314046, 5191102247248822272, 5189976364521848832,
    //7, 1226245742482522112,
    //3618502788666131213697322783095070105623107215331596699973092056135872020470, 2345108766317314046]

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.range_check);

    // Initialize data with preset values.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 18446744073709551615));
    try data.append(MaybeRelocatable.fromInt(u256, 5199546496550207487));
    try data.append(MaybeRelocatable.fromInt(u256, 4612389712311386111));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 2));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 7));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        8,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);

    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    // Run the program.
    var hint_processor: HintProcessor = .{};

    // Full takes 10 steps.
    // Execute the Cairo runner for 8 steps.
    try cairo_runner.runForSteps(8, false, &hint_processor);

    // Expect an error indicating the end of the program when attempting to execute the Cairo runner for 8 steps again.
    try expectError(
        CairoVMError.EndOfProgram,
        cairo_runner.runForSteps(8, false, &hint_processor),
    );
}

test "CairoRunner: run until next power of 2" {

    //Program used:
    //%builtins range_check
    //
    //func check_range{range_check_ptr}(num):
    //    # Check that 0 <= num < 2**64.
    //    [range_check_ptr] = num
    //    assert [range_check_ptr + 1] = 2 ** 64 - 1 - num
    //    let range_check_ptr = range_check_ptr + 2
    //    return()
    //end
    //
    //func main{range_check_ptr}():
    //    check_range(7)
    //    return()
    //end
    //
    //main = 8
    //data = [4612671182993129469, 5189976364521848832, 18446744073709551615,
    //5199546496550207487, 4612389712311386111, 5198983563776393216,
    //2, 2345108766317314046, 5191102247248822272, 5189976364521848832,
    //7, 1226245742482522112,
    //3618502788666131213697322783095070105623107215331596699973092056135872020470, 2345108766317314046]

    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.range_check);

    // Initialize data with preset values.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 4612671182993129469));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 18446744073709551615));
    try data.append(MaybeRelocatable.fromInt(u256, 5199546496550207487));
    try data.append(MaybeRelocatable.fromInt(u256, 4612389712311386111));
    try data.append(MaybeRelocatable.fromInt(u256, 5198983563776393216));
    try data.append(MaybeRelocatable.fromInt(u256, 2));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));
    try data.append(MaybeRelocatable.fromInt(u256, 5191102247248822272));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 7));
    try data.append(MaybeRelocatable.fromInt(u256, 1226245742482522112));
    try data.append(MaybeRelocatable.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020470));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        8,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        false,
    );

    // Initialize a CairoVM instance.
    const vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize a CairoRunner with an empty program, "plain" layout, and instructions.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );

    // Defer the deinitialization of the CairoRunner to ensure cleanup.
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    try cairo_runner.initBuiltins(true);

    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try expectEqual(Relocatable.init(4, 0), end);

    try cairo_runner.initVM();

    // Run the program.
    var hint_processor: HintProcessor = .{};

    // Full takes 10 steps.
    // Execute the Cairo runner for 1 step and then until the next power of two steps, ensuring a total of 10 steps.
    try cairo_runner.runForSteps(1, false, &hint_processor);
    try cairo_runner.runUntilNextPowerOf2(false, &hint_processor);

    // Assert that the current step count is 1.
    try expectEqual(@as(usize, 1), cairo_runner.vm.current_step);

    // Execute the Cairo runner for 1 step and then until the next power of two steps.
    try cairo_runner.runForSteps(1, false, &hint_processor);
    try cairo_runner.runUntilNextPowerOf2(false, &hint_processor);

    // Assert that the current step count is 2.
    try expectEqual(@as(usize, 2), cairo_runner.vm.current_step);

    // Execute the Cairo runner for 1 step and then until the next power of two steps.
    try cairo_runner.runForSteps(1, false, &hint_processor);
    try cairo_runner.runUntilNextPowerOf2(false, &hint_processor);

    // Assert that the current step count is 4.
    try expectEqual(@as(usize, 4), cairo_runner.vm.current_step);

    // Execute the Cairo runner for 1 step and then until the next power of two steps.
    try cairo_runner.runForSteps(1, false, &hint_processor);
    try cairo_runner.runUntilNextPowerOf2(false, &hint_processor);

    // Assert that the current step count is 8.
    try expectEqual(@as(usize, 8), cairo_runner.vm.current_step);

    // Execute the Cairo runner for 1 step.
    try cairo_runner.runForSteps(1, false, &hint_processor);

    // Expect an error indicating the end of the program when attempting to run until the next power of two steps.
    try expectError(
        CairoVMError.EndOfProgram,
        cairo_runner.runUntilNextPowerOf2(false, &hint_processor),
    );

    // Assert that the current step count is 10.
    try expectEqual(@as(usize, 10), cairo_runner.vm.current_step);
}

test "CairoRunner: checkDilutedCheckUsage without pool instance" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set diluted pool instance to null for testing without pool instance.
    cairo_runner.layout.diluted_pool_instance_def = null;

    // Call checkDilutedCheckUsage method and expect no error.
    try cairo_runner.checkDilutedCheckUsage(std.testing.allocator);
}

test "CairoRunner: checkDilutedCheckUsage without builtins runners" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set current step to simulate no built-in runners.
    cairo_runner.vm.current_step = 10000;

    // Call checkDilutedCheckUsage method and expect no error.
    try cairo_runner.checkDilutedCheckUsage(std.testing.allocator);
}

test "CairoRunner: checkDilutedCheckUsage with insufficient allocated cells" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set current step to simulate insufficient allocated cells.
    cairo_runner.vm.current_step = 100;

    // Call checkDilutedCheckUsage method and expect MemoryError.InsufficientAllocatedCells.
    try expectError(
        MemoryError.InsufficientAllocatedCells,
        cairo_runner.checkDilutedCheckUsage(std.testing.allocator),
    );
}

test "CairoRunner: checkDilutedCheckUsage with bitwise builtin" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set current step to simulate usage with bitwise builtin.
    cairo_runner.vm.current_step = 8192;

    // Append bitwise builtin runner.
    try cairo_runner.vm.builtin_runners.append(
        .{
            .Bitwise = BitwiseBuiltinRunner.init(
                &.{},
                true,
            ),
        },
    );

    // Call checkDilutedCheckUsage method and expect no error.
    try cairo_runner.checkDilutedCheckUsage(std.testing.allocator);
}

test "CairoRunner: endRun with a run that is already finished" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    cairo_runner.run_ended = true;

    var hint_processor: HintProcessor = .{};

    try expectError(
        CairoRunnerError.EndRunAlreadyCalled,
        cairo_runner.endRun(
            std.testing.allocator,
            true,
            false,
            &hint_processor,
            false,
        ),
    );
}

test "CairoRunner: endRun with a simple test" {
    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "plain",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    var hint_processor: HintProcessor = .{};

    try cairo_runner.endRun(
        std.testing.allocator,
        true,
        false,
        &hint_processor,
        false,
    );

    cairo_runner.run_ended = false;

    cairo_runner.relocated_memory.clearAndFree();

    try cairo_runner.endRun(
        std.testing.allocator,
        true,
        true,
        &hint_processor,
        false,
    );

    try expect(!cairo_runner.run_ended);
}

test "CairoRunner: checkMemoryUsage valid case" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.range_check);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoRunner instance with the created Program and CairoVM instances.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set a used size for a segment in the CairoVM.
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);

    // Check memory usage in the CairoRunner instance.
    try cairo_runner.checkMemoryUsage();
}

test "CairoRunner: checkMemoryUsage with error case" {
    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize and setup an OutputBuiltinRunner instance.
    var output_builtin = OutputBuiltinRunner.init(std.testing.allocator, false);
    try output_builtin.initSegments(vm.segments);

    // Append the OutputBuiltinRunner to the CairoVM's builtin runners list.
    try vm.builtin_runners.append(.{ .Output = output_builtin });

    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set used sizes for segments in the CairoVM.
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);
    try cairo_runner.vm.segments.segment_used_sizes.put(1, 12);

    // Set up memory for the VM with specific addresses and values.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{0} },
            .{ .{ 0, 1 }, .{1} },
            .{ .{ 0, 2 }, .{1} },
        },
    );
    // Deallocate data memory after the test.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Mark memory as accessed in CairoVM.
    cairo_runner.vm.segments.memory.markAsAccessed(.{});

    // Expect an error of insufficient allocated cells when checking memory usage.
    try expectError(MemoryError.InsufficientAllocatedCells, cairo_runner.checkMemoryUsage());
}

test "CairoRunner: checkUsedCells valid case" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.range_check);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoRunner instance with the created Program and CairoVM instances.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set used sizes for segments in the CairoVM.
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);

    // Set diluted pool instance definition to null in CairoRunner layout.
    cairo_runner.layout.diluted_pool_instance_def = null;

    // Check used cells in the CairoRunner instance.
    try cairo_runner.checkUsedCells(std.testing.allocator);
}

test "CairoRunner: checkUsedCells with insufficient allocated cells MinStepNotReached" {
    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = false, .enable_trace = true },
    );

    // Initialize and append a RangeCheckBuiltinRunner to the CairoVM's builtin runners list.
    try vm.builtin_runners.append(
        .{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) },
    );

    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set up memory for the VM with specific addresses and values.
    try cairo_runner.vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{0x80ff80000530} }},
    );
    // Deallocate data memory after the test.
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Append an entry to the CairoVM's trace context state enabled entries list.
    try cairo_runner.vm.trace.?.append(.{ .pc = .{}, .ap = .{}, .fp = .{} });

    // Compute effective size of segments in CairoVM.
    _ = try cairo_runner.vm.segments.computeEffectiveSize(false);

    // Expect an error of MinStepNotReached when checking used cells.
    try expectError(
        InsufficientAllocatedCellsError.MinStepNotReached,
        cairo_runner.checkUsedCells(std.testing.allocator),
    );
}

test "CairoRunner: checkUsedCells with insufficient allocated cells" {
    // Initialize a CairoVM instance.
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{ .proof_mode = true, .enable_trace = true },
    );

    // Mark specific memory addresses as accessed in the CairoVM.
    vm.segments.memory.markAsAccessed(Relocatable.init(1, 0));
    vm.segments.memory.markAsAccessed(Relocatable.init(1, 3));

    // Initialize and setup an OutputBuiltinRunner instance.
    var output_builtin = OutputBuiltinRunner.init(std.testing.allocator, true);
    try output_builtin.initSegments(vm.segments);

    // Append the OutputBuiltinRunner to the CairoVM's builtin runners list.
    try vm.builtin_runners.append(.{ .Output = output_builtin });

    // Create a CairoRunner instance for testing.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        try Program.initDefault(std.testing.allocator, true),
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        vm,
        true,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set used sizes for segments in the CairoVM.
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);
    try cairo_runner.vm.segments.segment_used_sizes.put(1, 12);

    // Expect an error of insufficient allocated cells when checking used cells.
    try expectError(
        MemoryError.InsufficientAllocatedCells,
        cairo_runner.checkUsedCells(std.testing.allocator),
    );
}

test "CairoRunner: checkUsedCells with diluted check error" {
    // Initialize a list of built-in functions.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.range_check);
    try builtins.append(BuiltinName.output);

    // Initialize data structures required for a program.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a Program instance with the specified parameters.
    const program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
        true,
    );

    // Initialize a CairoRunner instance with the created Program and CairoVM instances.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{},
        ),
        false,
    );
    defer cairo_runner.deinit(std.testing.allocator);

    // Set used sizes for segments in the CairoVM.
    try cairo_runner.vm.segments.segment_used_sizes.put(0, 4);

    // Expect an error of insufficient allocated cells when checking used cells.
    try expectError(
        MemoryError.InsufficientAllocatedCells,
        cairo_runner.checkUsedCells(std.testing.allocator),
    );
}

test "CairoRunner: endRun in proof mode with insufficient allocated cells" {
    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.posix.realpath("cairo_programs/proof_programs/fibonacci.json", &buffer);
    // Parse the JSON file into a `ProgramJson` structure
    var parsed_program = try ProgramJson.parseFromFile(std.testing.allocator, path);
    defer parsed_program.deinit();

    // Specify the entrypoint identifier
    var entrypoint: []const u8 = "main";
    // Parse the program JSON into a `Program` structure
    const program = try parsed_program.value.parseProgramJson(
        std.testing.allocator,
        &entrypoint,
        false,
    );

    // Initialize a CairoRunner instance with the created Program and CairoVM instances.
    var cairo_runner = try CairoRunner.init(
        std.testing.allocator,
        program,
        "all_cairo",
        ArrayList(MaybeRelocatable).init(std.testing.allocator),
        try CairoVM.init(
            std.testing.allocator,
            .{ .proof_mode = true, .enable_trace = true },
        ),
        true,
    );
    defer cairo_runner.deinit(std.testing.allocator);
    defer cairo_runner.vm.segments.memory.deinitData(std.testing.allocator);

    // Initialize a HintProcessor instance.
    var hint_processor: HintProcessor = .{};

    // Initialize builtins, segments, main entry point, and VM.
    try cairo_runner.initBuiltins(true);
    try cairo_runner.initSegments(null);
    const end = try cairo_runner.initMainEntrypoint();
    try cairo_runner.initVM();

    // Run the program until reaching the specified PC.
    try cairo_runner.runUntilPC(end, false, &hint_processor);
}
