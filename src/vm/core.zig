// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const starknet_felt = @import("../math/fields/starknet.zig");

// Local imports.
const segments = @import("memory/segments.zig");
const relocatable = @import("memory/relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;
const instructions = @import("instructions.zig");
const RunContext = @import("run_context.zig").RunContext;
const CairoVMError = @import("error.zig").CairoVMError;
const MemoryError = @import("error.zig").MemoryError;
const TraceError = @import("error.zig").TraceError;
const ExecScopeError = @import("error.zig").ExecScopeError;
const Config = @import("config.zig").Config;
const TraceContext = @import("trace_context.zig").TraceContext;
const TraceEntry = @import("trace_context.zig").TraceEntry;
const RelocatedTraceEntry = @import("trace_context.zig").RelocatedTraceEntry;
const RangeCheckBuiltinRunner = @import("builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;
const SignatureBuiltinRunner = @import("builtins/builtin_runner/signature.zig").SignatureBuiltinRunner;
const BuiltinRunner = @import("builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const builtin_runner = @import("builtins/builtin_runner/builtin_runner.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HashBuiltinRunner = @import("./builtins/builtin_runner/hash.zig").HashBuiltinRunner;
const Instruction = instructions.Instruction;
const Opcode = instructions.Opcode;
const Error = @import("./error.zig");
const HintProcessor = @import("../hint_processor/hint_processor_def.zig").CairoVMHintProcessor;
const ExecutionScopes = @import("types/execution_scopes.zig").ExecutionScopes;
const HintData = @import("../hint_processor/hint_processor_def.zig").HintData;
const HintRange = @import("../vm/types/program.zig").HintRange;

const cfg = @import("cfg");

const decoder = @import("../vm/decoding/decoder.zig");

/// Represents the Cairo VM.
pub const CairoVM = struct {
    const Self = @This();

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************

    /// The memory allocator.
    allocator: Allocator,
    /// The run context.
    run_context: RunContext,
    /// ArrayList of built-in runners
    builtin_runners: ArrayList(BuiltinRunner),
    /// The memory segment manager.
    segments: *segments.MemorySegmentManager,
    /// Whether the run is finished or not.
    is_run_finished: bool = false,
    /// VM trace
    trace: ?std.ArrayList(TraceEntry) = null,
    relocated_trace: ?std.ArrayList(RelocatedTraceEntry) = null,
    /// Current Step
    current_step: usize = 0,
    /// Rc limits
    rc_limits: ?struct { isize, isize } = null,
    skip_instruction_execution: bool = false,
    /// Relocation table
    relocation_table: ?std.ArrayList(usize) = null,
    /// ArrayList containing instructions. May hold null elements.
    /// Used as an instruction cache within the CairoVM instance.
    instruction_cache: ArrayList(?Instruction),

    relocated_memory: ?std.AutoHashMap(u32, Felt252) = null,

    // ************************************************************
    // *             MEMORY ALLOCATION AND DEALLOCATION           *
    // ************************************************************

    pub fn initV2(allocator: Allocator, trace_enabled: bool) !Self {

        // Initialize the memory segment manager.
        const memory_segment_manager = try segments.MemorySegmentManager.init(allocator);
        errdefer memory_segment_manager.deinit();
        // Initialize the trace context.
        var trace: ?std.ArrayList(TraceEntry) = if (trace_enabled) try std.ArrayList(TraceEntry).initCapacity(allocator, 100) else null;
        errdefer if (trace != null) trace.?.deinit();
        // Initialize the run context.
        const run_context = .{};
        // Initialize the built-in runners.
        const builtin_runners = ArrayList(BuiltinRunner).init(allocator);
        errdefer builtin_runners.deinit();
        // Initialize the instruction cache.
        const instruction_cache = try ArrayList(?Instruction).initCapacity(allocator, 100);
        errdefer instruction_cache.deinit();

        return .{
            .allocator = allocator,
            .run_context = run_context,
            .builtin_runners = builtin_runners,
            .segments = memory_segment_manager,
            .instruction_cache = instruction_cache,
            .trace = trace,
        };
    }

    /// Creates a new Cairo VM.
    /// # Arguments
    /// - `allocator`: The allocator to use for the VM.
    /// - `config`: Configurations used to initialize the VM.
    /// # Returns
    /// - `CairoVM`: The created VM.
    /// # Errors
    /// - If a memory allocation fails.
    pub fn init(allocator: Allocator, config: Config) !Self {
        return Self.initV2(allocator, config.enable_trace);
    }

    /// Safely deallocates resources used by the CairoVM instance.
    ///
    /// This function ensures safe deallocation of various components within the CairoVM instance,
    /// including the memory segment manager, run context, trace context, built-in runners, and the instruction cache.
    ///
    /// # Safety
    /// This function assumes proper initialization of the CairoVM instance and must be called
    /// to avoid memory leaks and ensure proper cleanup.
    pub fn deinit(self: *Self) void {
        // Deallocate the memory segment manager.
        self.segments.deinit();
        // Deallocate trace context.
        if (self.trace) |trace| trace.deinit();
        if (self.relocated_trace) |trace| trace.deinit();
        // Loop through the built-in runners and deallocate their resources.
        for (self.builtin_runners.items) |*builtin| {
            builtin.deinit();
        }
        // Deallocate built-in runners.
        self.builtin_runners.deinit();
        if (self.relocation_table) |*r| {
            r.deinit();
        }
        // Deallocate instruction cache
        self.instruction_cache.deinit();
    }

    // ************************************************************
    // *                        METHODS                           *
    // ************************************************************

    /// Computes and returns the effective size of memory segments.
    ///
    /// This function iterates through the memory segments, calculates their effective sizes, and
    /// updates the segment sizes map accordingly. It ensures that the map reflects the maximum
    /// offset used in each segment.
    ///
    /// # Returns
    ///
    /// An AutoArrayHashMap representing the computed effective sizes of memory segments.
    pub fn computeSegmentsEffectiveSizes(self: *Self, allow_temp_segments: bool) !std.ArrayList(usize) {
        return self.segments.computeEffectiveSize(allow_temp_segments);
    }

    /// Adds a memory segment to the Cairo VM and returns the first address of the new segment.
    ///
    /// This function internally calls `addSegment` on the memory segments manager, creating a new
    /// relocatable address for the new segment. It increments the number of segments in the VM.
    ///
    /// # Returns
    ///
    /// The relocatable address representing the first address of the new memory segment.
    pub fn addMemorySegment(self: *Self) !Relocatable {
        return try self.segments.addSegment();
    }

    /// Retrieves a value from the memory at the specified relocatable address.
    ///
    /// This function internally calls `get` on the memory segments manager, returning the value
    /// at the given address. It handles the possibility of an out-of-bounds access and returns
    /// an error of type `MemoryOutOfBounds` in such cases.
    ///
    /// # Arguments
    ///
    /// - `address`: The relocatable address to retrieve the value from.
    /// # Returns
    ///
    /// - The value at the specified address, or an error of type `MemoryOutOfBounds`.
    pub fn getRelocatable(
        self: *Self,
        address: Relocatable,
    ) !Relocatable {
        return self.segments.memory.getRelocatable(address);
    }

    /// Gets a reference to the list of built-in runners in the Cairo VM.
    ///
    /// This function returns a mutable reference to the list of built-in runners,
    /// allowing access and modification of the Cairo VM's built-in runner instances.
    ///
    /// # Returns
    ///
    /// A mutable reference to the list of built-in runners.
    pub fn getBuiltinRunners(self: *Self) *ArrayList(BuiltinRunner) {
        return &self.builtin_runners;
    }

    pub fn getSignatureBuiltin(self: *const Self) !*SignatureBuiltinRunner {
        for (self.builtin_runners.items) |*runner|
            switch (runner.*) {
                .Signature => |*signature_builtin| return signature_builtin,
                else => {},
            };

        return CairoVMError.NoSignatureBuiltin;
    }

    pub fn insertInMemory(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        value: MaybeRelocatable,
    ) !void {
        try self.segments.memory.set(allocator, address, value);
    }

    /// Retrieves the used size of a memory segment by its index, if available; otherwise, returns null.
    ///
    /// This function internally calls `getSegmentUsedSize` on the memory segments manager, returning
    /// the used size of the segment at the specified index. It handles the possibility of the size not
    /// being computed and returns null if not available.
    ///
    /// # Parameters
    ///
    /// - `index` (u32): The index of the memory segment.
    /// # Returns
    ///
    /// - The used size of the segment at the specified index, or null if not computed.
    pub fn getSegmentUsedSize(self: *Self, index: usize) ?usize {
        return self.segments.getSegmentUsedSize(index);
    }

    /// Retrieves the size of a memory segment by its index, if available; otherwise, computes it.
    ///
    /// This function internally calls `getSegmentSize` on the memory segments manager, attempting
    /// to retrieve the size of the segment at the specified index. If the size is not available,
    /// it computes the effective size using `getSegmentUsedSize` and returns it.
    ///
    /// # Parameters
    ///
    /// - `index` (u32): The index of the memory segment.
    /// # Returns
    ///
    /// - The size of the segment at the specified index, or a computed effective size if not available.
    pub fn getSegmentSize(self: *Self, index: usize) ?usize {
        return self.segments.getSegmentSize(index);
    }

    /// Retrieves a `Felt252` value from the memory at the specified relocatable address in the Cairo VM.
    ///
    /// This function internally calls `getFelt` on the memory segments manager, attempting
    /// to retrieve a `Felt252` value at the given address. It handles the possibility of an
    /// out-of-bounds memory access and returns an error if needed.
    ///
    /// # Arguments
    ///
    /// - `address`: The relocatable address to retrieve the `Felt252` value from.
    /// # Returns
    ///
    /// - The `Felt252` value at the specified address, or an error if not available.
    pub fn getFelt(self: *Self, address: Relocatable) !Felt252 {
        return self.segments.memory.getFelt(address);
    }

    pub fn stepHintExtensive(
        self: *Self,
        hint_processor: HintProcessor,
        exec_scopes: *ExecutionScopes,
        hint_datas: *std.ArrayList(HintData),
        hint_ranges: *std.AutoHashMap(Relocatable, HintRange),
        constants: *std.StringHashMap(Felt252),
    ) !void {
        if (hint_ranges.get(self.run_context.getPC())) |hint_range| {
            // Execute each hint for the given range
            for (hint_range.start..hint_range.start + hint_range.length) |idx| {
                const hint_data = if (idx < hint_datas.items.len) &hint_datas.items[idx] else return CairoVMError.Unexpected;

                var hint_extension = try hint_processor.executeHintExtensive(self.allocator, self, hint_data, constants, exec_scopes);
                defer hint_extension.deinit();

                var it = hint_extension.iterator();
                while (it.next()) |el| {
                    if (el.value_ptr.items.len != 0) {
                        try hint_ranges.put(el.key_ptr.*, .{ .start = hint_datas.items.len, .length = el.value_ptr.items.len });
                        try hint_datas.appendSlice(el.value_ptr.items);
                    }
                }
            }
        }
    }

    pub fn stepHintNotExtensive(
        self: *Self,
        hint_processor: HintProcessor,
        exec_scopes: *ExecutionScopes,
        hint_datas: []HintData,
        constants: *std.StringHashMap(Felt252),
    ) !void {
        for (hint_datas) |*hint_data| {
            try hint_processor.executeHint(self.allocator, self, hint_data, constants, exec_scopes);
        }
    }

    /// Executes the next instruction in the Cairo VM.
    ///
    /// This function retrieves the next instruction based on the program counter (PC) in the run context.
    /// It checks whether the instruction cache contains the instruction corresponding to the PC.
    /// If not, it decodes the current instruction and adds it to the cache.
    /// Then, it executes the instruction using the `runInstruction` function.
    /// If `skip_instruction_execution` is set to true, it advances the program counter accordingly.
    ///
    /// # Parameters
    /// - `self`: A pointer to the Cairo VM instance.
    /// - `allocator`: The allocator used for memory operations.
    /// # Errors
    /// - If accessing an unknown memory cell occurs.
    pub inline fn stepInstruction(self: *Self) !void {
        const inst = if (self.run_context.pc.segment_index == 0) value: {
            // Run instructions from the program segment, using the instruction cache.
            const pc = self.run_context.pc.offset;

            // Ensure PC is within the bounds of the memory segment.
            if (self.segments.memory.data.items[0].items.len <= pc)
                return MemoryError.UnknownMemoryCell;

            // Resize the instruction cache if necessary.
            const new_cache_len = @max(pc + 1, self.instruction_cache.items.len);
            if (self.instruction_cache.items.len < new_cache_len) {
                if (self.instruction_cache.capacity < new_cache_len)
                    try self.instruction_cache.ensureTotalCapacityPrecise(self.instruction_cache.capacity * 2);

                self.instruction_cache.appendNTimesAssumeCapacity(null, new_cache_len - self.instruction_cache.items.len);
            }

            // Get the instruction related to the PC.
            const instruction = &self.instruction_cache.items[pc];

            // If the instruction does not exist in the cache, decode the current instruction.
            if (instruction.* == null) {
                instruction.* = try self.decodeCurrentInstruction();
            }

            break :value instruction.*.?;
        } else try self.decodeCurrentInstruction();

        // Execute the instruction if skip_instruction_execution is false.
        if (!self.skip_instruction_execution) {
            try self.runInstruction(
                inst,
            );
        } else {
            // Advance the program counter if skip_instruction_execution is true.
            self.run_context.pc = try self.run_context.pc.addUint(inst.size());
            self.skip_instruction_execution = false;
        }
    }

    /// Do a single step of the VM with not extensive hints.
    /// Process an instruction cycle using the typical fetch-decode-execute cycle.
    pub inline fn stepNotExtensive(
        self: *Self,
        hint_processor: HintProcessor,
        exec_scopes: *ExecutionScopes,
        hint_datas: []HintData,
        constants: *std.StringHashMap(Felt252),
    ) !void {
        try self.stepHintNotExtensive(
            hint_processor,
            exec_scopes,
            hint_datas,
            constants,
        );
        try self.stepInstruction();
    }

    /// Do a single step of the VM with extensive hints.
    /// Process an instruction cycle using the typical fetch-decode-execute cycle.
    pub fn stepExtensive(
        self: *Self,
        hint_processor: HintProcessor,
        exec_scopes: *ExecutionScopes,
        hint_datas: *std.ArrayList(HintData),
        hint_ranges: *std.AutoHashMap(Relocatable, HintRange),
        constants: *std.StringHashMap(Felt252),
    ) !void {
        try self.stepHintExtensive(
            hint_processor,
            exec_scopes,
            hint_datas,
            hint_ranges,
            constants,
        );
        try self.stepInstruction();
    }

    /// Insert Operands only after checking if they were deduced.
    // # Arguments
    /// - `allocator`: allocator where OperandsResult stored.
    /// - `op`: OperandsResult object that stores all operands.
    pub inline fn insertDeducedOperands(self: *Self, op: OperandsResult) !void {
        if (op.wasOp0Deducted())
            try self.segments.memory.set(self.allocator, op.op_0_addr, op.op_0);

        if (op.wasOp1Deducted())
            try self.segments.memory.set(self.allocator, op.op_1_addr, op.op_1);

        if (op.wasDestDeducted())
            try self.segments.memory.set(self.allocator, op.dst_addr, op.dst);
    }

    /// Runs a specific instruction in the Cairo VM.
    ///
    /// This function executes a single instruction in the Cairo VM by fetching, decoding, and
    /// executing the instruction. It updates the VM's registers, traces the instruction (if
    /// tracing is enabled), computes and inserts operands into memory, and marks memory accesses.
    ///
    /// # Parameters
    ///
    /// - `self`: A mutable reference to the CairoVM instance.
    /// - `allocator`: The allocator used for memory operations.
    /// - `instruction`: A pointer to the instruction to run.
    ///
    /// # Errors
    ///
    /// This function may return an error of type `CairoVMError.InstructionEncodingError` if there
    /// is an issue with encoding or decoding the instruction.
    ///
    /// # Tracing
    ///
    /// If tracing is not disabled, this function logs the current state, including program counter (`pc`),
    /// argument pointer (`ap`), and frame pointer (`fp`) to the trace context before executing the instruction.
    ///
    /// # Operations
    ///
    /// ## Memory Operations
    ///
    /// - Computes operands for the instruction using the `computeOperands` function.
    /// - Inserts deduced operands into memory using the `insertDeducedOperands` function.
    /// - Performs opcode-specific assertions on operands using the `opcodeAssertions` function.
    ///
    /// ## Register Updates
    ///
    /// - Updates registers based on the instruction and operands using the `updateRegisters` function.
    ///
    /// ## Relocation Limits
    ///
    /// - Calculates and updates relocation limits based on the instruction's offset fields.
    ///
    /// ## Memory Access Marking
    ///
    /// - Marks memory accesses for the instruction's destination and operands.
    ///
    /// ## Step Counter
    ///
    /// - Increments the current step counter after executing the instruction.
    ///
    /// # Safety
    ///
    /// This function assumes proper initialization of the CairoVM instance and must be called in
    /// a controlled environment to ensure the correct execution of instructions and memory operations.
    pub inline fn runInstruction(
        self: *Self,
        instruction: Instruction,
    ) !void {
        // Check if tracing is disabled and log the current state if not.
        if (self.trace) |*trace| {
            if (trace.capacity <= trace.items.len)
                try trace.ensureTotalCapacityPrecise(trace.capacity * 2);

            trace.appendAssumeCapacity(
                .{
                    .pc = self.run_context.pc,
                    .ap = self.run_context.ap,
                    .fp = self.run_context.fp,
                },
            );
        }

        // Compute operands for the instruction.
        const operands_result = try self.computeOperands(instruction);

        // Insert deduced operands into memory.
        try self.insertDeducedOperands(operands_result);

        // Perform opcode-specific assertions on operands using the `opcodeAssertions` function.
        try self.opcodeAssertions(instruction, operands_result);

        // Constants for offset bit manipulation.
        const OFFSET: u16 = 1 << 15;
        const off_0 = @as(isize, instruction.off_0) + OFFSET;
        const off_1 = @as(isize, instruction.off_1) + OFFSET;
        const off_2 = @as(isize, instruction.off_2) + OFFSET;

        // Calculate and update relocation limits.
        self.rc_limits = if (self.rc_limits) |limits| .{
            @min(limits[0], off_0, off_1, off_2),
            @max(limits[1], off_0, off_1, off_2),
        } else .{
            @min(off_0, off_1, off_2),
            @max(off_0, off_1, off_2),
        };

        // Mark memory accesses for the instruction.
        self.segments.memory.markAsAccessed(operands_result.dst_addr);
        self.segments.memory.markAsAccessed(operands_result.op_0_addr);
        self.segments.memory.markAsAccessed(operands_result.op_1_addr);

        // Update registers based on the instruction and operands.
        try self.updateRegisters(instruction, operands_result);

        // Increment the current step counter.
        self.current_step += 1;
    }

    /// Compute and retrieve the necessary operands for executing a given instruction.
    ///
    /// This function resolves memory addresses, deduces operands based on context,
    /// and computes the result of the instruction.
    ///
    /// It operates within a segmented memory
    /// environment and handles the computation of operands, destinations, and results.
    ///
    /// # Arguments
    /// - `instruction`: The instruction to compute operands for.
    /// - `allocator`: The memory allocator used for computation.
    ///
    /// # Returns
    /// A structured `OperandsResult` containing computed operands, the result, and destinations.
    pub inline fn computeOperands(
        self: *Self,
        instruction: Instruction,
    ) !OperandsResult {
        // Create a default OperandsResult to store the computed operands.
        var op_res: OperandsResult = .{};

        // Compute the destination address of the instruction.
        op_res.dst_addr = try self.run_context.computeDstAddr(instruction);
        const dst_op = self.segments.memory.get(op_res.dst_addr);

        // Compute the first operand address.
        op_res.op_0_addr = try self.run_context.computeOp0Addr(instruction);

        const op_0_op = self.segments.memory.get(op_res.op_0_addr);

        // Compute the second operand address based on the first operand.
        op_res.op_1_addr = try self.run_context.computeOp1Addr(
            instruction,
            op_0_op,
        );
        const op_1_op = self.segments.memory.get(op_res.op_1_addr);

        // Deduce the first operand if retrieval from memory fails.
        if (op_0_op) |op_0| {
            op_res.op_0 = op_0;
        } else {
            // Set flag to compute and deduce op_0.
            op_res.setOp0(1);
            // Compute op_0 based on specific deductions.
            op_res.op_0 = try self.computeOp0Deductions(
                op_res.op_0_addr,
                &op_res.res,
                instruction,
                dst_op,
                op_1_op,
            );
        }

        // Deduce the second operand if retrieval from memory fails.
        if (op_1_op) |op_1| {
            op_res.op_1 = op_1;
        } else {
            // Set flag to compute and deduce op_1.
            op_res.setOp1(1);
            // Compute op_1 based on specific deductions.
            op_res.op_1 = try self.computeOp1Deductions(
                op_res.op_1_addr,
                &op_res.res,
                instruction,
                dst_op,
                op_res.op_0,
            );
        }

        // Compute the result if it hasn't been computed.
        if (op_res.res == null) {
            op_res.res = try instruction.computeRes(op_res.op_0, op_res.op_1);
        }

        // Retrieve the destination if not already available.op_0_op
        if (dst_op) |dst| {
            op_res.dst = dst;
        } else {
            // Set flag to compute and deduce the destination.
            op_res.setDst(1);
            // Compute the destination based on certain conditions.
            op_res.dst = try self.deduceDst(instruction, op_res.res);
        }

        // Return the computed operands and result.
        return op_res;
    }

    /// Compute Op0 deductions based on the provided instruction, destination, and Op1.
    ///
    /// This function first attempts to deduce Op0 using built-in deductions. If that returns a null,
    /// it falls back to deducing Op0 based on the provided destination and Op1.
    ///
    /// ## Arguments
    /// - `op_0_addr`: The address of the operand to deduce.
    /// - `instruction`: The instruction to deduce the operand for.
    /// - `dst`: The destination of the instruction.
    /// - `op1`: The Op1 operand.
    ///
    /// ## Returns
    /// - `MaybeRelocatable`: The deduced Op0 operand or an error if deducing Op0 fails.
    pub inline fn computeOp0Deductions(
        self: *Self,
        op_0_addr: Relocatable,
        res: *?MaybeRelocatable,
        instruction: Instruction,
        dst: ?MaybeRelocatable,
        op1: ?MaybeRelocatable,
    ) !MaybeRelocatable {
        if (try self.deduceMemoryCell(op_0_addr)) |op0| {
            return op0;
        }
        const op0_deductions = try self.deduceOp0(instruction, dst, op1);
        if (res.* == null) res.* = op0_deductions.res;

        return op0_deductions.op_0 orelse CairoVMError.FailedToComputeOp0;
    }

    /// Compute Op1 deductions based on the provided instruction, destination, and Op0.
    ///
    /// This function attempts to deduce Op1 using built-in deductions. If that returns a null,
    /// it falls back to deducing Op1 based on the provided destination, Op0, and the result.
    ///
    /// ## Arguments
    /// - `op1_addr`: The address of the operand to deduce.
    /// - `res`: The result of the computation.
    /// - `instruction`: The instruction to deduce the operand for.
    /// - `dst_op`: The destination operand.
    /// - `op0`: The Op0 operand.
    ///
    /// ## Returns
    /// - `MaybeRelocatable`: The deduced Op1 operand or an error if deducing Op1 fails.
    pub inline fn computeOp1Deductions(
        self: *Self,
        op1_addr: Relocatable,
        res: *?MaybeRelocatable,
        instruction: Instruction,
        dst_op: ?MaybeRelocatable,
        op0: ?MaybeRelocatable,
    ) !MaybeRelocatable {
        if (try self.deduceMemoryCell(op1_addr)) |op1|
            return op1;

        const op1_deductions = try instruction.deduceOp1(dst_op, op0);
        if (res.* == null) res.* = op1_deductions.res;
        return op1_deductions.op_1 orelse CairoVMError.FailedToComputeOp1;
    }

    /// Verifies the auto deductions for all memory cells managed by the VM's builtins.
    ///
    /// This function iterates over all builtins and their corresponding memory segments.
    /// For each memory cell, it attempts to deduce the value using the builtin's logic.
    /// If the deduced value does not match the actual value in memory, an error is returned.
    ///
    /// ## Arguments
    /// - `allocator`: The allocator instance to use for memory operations.
    ///
    /// ## Returns
    /// - `void`: Returns nothing on success.
    /// - `CairoVMError.InconsistentAutoDeduction`: Returns an error if a deduced value does not match the memory.
    pub fn verifyAutoDeductions(self: *const Self, allocator: Allocator) !void {
        for (self.builtin_runners.items) |*builtin| {
            const segment_index = builtin.base();

            for (self.segments.memory.data.items[segment_index].items, 0..) |value, offset| {
                if (value.getValue()) |v| {
                    const addr = Relocatable.init(@intCast(segment_index), offset);
                    const deduced_memory_cell = try builtin.deduceMemoryCell(allocator, addr, self.segments.memory) orelse continue;
                    if (!deduced_memory_cell.eq(v)) {
                        return CairoVMError.InconsistentAutoDeduction;
                    }
                }
            }
        }
    }

    /// Verifies the auto deductions for a given memory address.
    ///
    /// This function checks if the value deduced by the builtin matches the current value
    /// at the given address in the VM's memory. If they do not match, it returns an error
    /// indicating an inconsistent auto deduction.
    ///
    /// ## Arguments
    /// - `allocator`: The allocator instance to use for memory operations.
    /// - `addr`: The memory address to verify.
    /// - `builtin`: The BuiltinRunner instance used for deducing the memory cell.
    ///
    /// ## Returns
    /// - `void`: Returns nothing on success.
    /// - `CairoVMError.InconsistentAutoDeduction`: Returns an error if the deduced value does not match the memory.
    pub fn verifyAutoDeductionsForAddr(
        self: *const Self,
        allocator: Allocator,
        addr: Relocatable,
        builtin: *BuiltinRunner,
    ) !void {
        const value = try builtin.deduceMemoryCell(
            allocator,
            addr,
            self.segments.memory,
        ) orelse return;
        const current_value = self.segments.memory.get(addr) orelse return;
        if (!value.eq(current_value))
            return CairoVMError.InconsistentAutoDeduction;
    }

    /// Attempts to deduce `op0` and `res` for an instruction, given `dst` and `op1`.
    ///
    /// # Arguments
    /// - `inst`: The instruction to deduce `op0` and `res` for.
    /// - `dst`: The destination of the instruction.
    /// - `op1`: The first operand of the instruction.
    ///
    /// # Returns
    /// - `Tuple`: A tuple containing the deduced `op0` and `res`.
    pub fn deduceOp0(
        self: *const Self,
        inst: Instruction,
        dst: ?MaybeRelocatable,
        op1: ?MaybeRelocatable,
    ) !struct {
        /// The computed operand Op0.
        op_0: ?MaybeRelocatable = null,
        /// The result of the operation involving Op0.
        res: ?MaybeRelocatable = null,
    } {
        switch (inst.opcode) {
            .Call => {
                return .{
                    .op_0 = MaybeRelocatable.fromRelocatable(try self.run_context.pc.addUint(inst.size())),
                };
            },
            .AssertEq => {
                if (dst == null or op1 == null) return .{};
                if (inst.res_logic == .Add) {
                    return .{
                        .op_0 = try dst.?.sub(op1.?),
                        .res = dst,
                    };
                } else if (dst.?.isFelt() and op1.?.isFelt() and !op1.?.felt.isZero()) {
                    return .{
                        .op_0 = MaybeRelocatable.fromFelt(try dst.?.felt.div(op1.?.felt)),
                        .res = dst,
                    };
                }
            },
            else => return .{},
        }
        return .{};
    }

    /// Updates the value of PC according to the executed instruction.
    /// # Arguments
    /// - `instruction`: The instruction that was executed.
    /// - `operands`: The operands of the instruction.
    pub inline fn updatePc(
        self: *Self,
        instruction: Instruction,
        operands: OperandsResult,
    ) !void {
        self.run_context.pc = switch (instruction.pc_update) {
            // PC update regular
            .Regular => // Update the PC.
            try self.run_context.pc.addUint(instruction.size()),
            // PC update jump
            .Jump =>
            // Check that the res is not null.
            if (operands.res) |val|
                val.intoRelocatable() catch
                    return error.PcUpdateJumpResNotRelocatable
            else
                return error.ResUnconstrainedUsedWithPcUpdateJump,
            // PC update Jump Rel
            .JumpRel =>
            // Check that the res is not null.
            if (operands.res) |val|
                try self.run_context.pc.addFelt(val.intoFelt() catch return error.PcUpdateJumpRelResNotFelt)
            else
                return error.ResUnconstrainedUsedWithPcUpdateJumpRel,
            // PC update Jnz
            .Jnz => if (operands.dst.isZero())
                try self.run_context.pc.addUint(instruction.size())
            else
                try self.run_context.pc.addMaybeRelocatable(operands.op_1),
        };
    }

    /// Updates the value of AP according to the executed instruction.
    /// # Arguments
    /// - `instruction`: The instruction that was executed.
    /// - `operands`: The operands of the instruction.
    pub inline fn updateAp(
        self: *Self,
        instruction: Instruction,
        operands: OperandsResult,
    ) !void {
        self.run_context.ap = switch (instruction.ap_update) {
            // AP update Add
            .Add =>
            // Check that Res is not null.
            if (operands.res) |val|
                // Update AP.
                (try self.run_context.getAP().addMaybeRelocatable(val)).offset
            else
                return error.ApUpdateAddResUnconstrained,
            // AP update Add1
            .Add1 => self.run_context.ap + 1,
            // AP update Add2
            .Add2 => self.run_context.ap + 2,
            // AP update regular
            .Regular => return,
        };
    }

    /// Updates the value of AP according to the executed instruction.
    /// # Arguments
    /// - `instruction`: The instruction that was executed.
    /// - `operands`: The operands of the instruction.
    pub inline fn updateFp(
        self: *Self,
        instruction: Instruction,
        operands: OperandsResult,
    ) !void {
        self.run_context.fp = switch (instruction.fp_update) {
            // FP update Add + 2
            .APPlus2 => self.run_context.ap + 2,
            // FP update Dst
            .Dst => switch (operands.dst) {
                .relocatable => |rel| rel.offset,
                .felt => |f| try f.toInt(usize),
            },
            else => return,
        };
    }

    /// Updates the registers (fp, ap, and pc) based on the given instruction and operands.
    ///
    /// This function internally calls `updateFp`, `updateAp`, and `updatePc` to update the respective registers.
    ///
    /// # Arguments
    ///
    /// - `instruction`: The instruction to determine register updates.
    /// - `operands`: The result of the instruction's operands.
    /// # Returns
    ///
    /// - Returns `void` on success, an error on failure.
    pub inline fn updateRegisters(
        self: *Self,
        instruction: Instruction,
        operands: OperandsResult,
    ) !void {
        try self.updateFp(instruction, operands);
        try self.updateAp(instruction, operands);
        try self.updatePc(instruction, operands);
    }

    /// Deduces the destination register for a given instruction.
    ///
    /// This function analyzes the opcode of the instruction and deduces the destination register accordingly.
    /// For `.AssertEq` opcode, it returns the value of the result if available, otherwise `CairoVMError.NoDst`.
    /// For `.Call` opcode, it returns a new relocatable value based on the frame pointer.
    /// For other opcodes, it returns `CairoVMError.NoDst`.
    ///
    /// # Arguments
    ///
    /// - `instruction`: The instruction to deduce the destination for.
    /// - `res`: The result of the instruction's operands (nullable).
    /// # Returns
    ///
    /// - Returns the deduced destination register, or an error if no destination is deducible.
    pub fn deduceDst(
        self: *const Self,
        instruction: Instruction,
        res: ?MaybeRelocatable,
    ) !MaybeRelocatable {
        return switch (instruction.opcode) {
            .AssertEq => if (res) |r| r else CairoVMError.NoDst,
            .Call => MaybeRelocatable.fromRelocatable(.{ .segment_index = 1, .offset = self.run_context.fp }),
            else => CairoVMError.NoDst,
        };
    }

    /// Applies the corresponding builtin's deduction rules if addr's segment index corresponds to a builtin segment
    /// Returns null if there is no deduction for the address
    /// # Arguments
    /// - `address`: The address to deduce.
    /// # Returns
    /// - `MaybeRelocatable`: The deduced value.
    pub fn deduceMemoryCell(
        self: *Self,
        address: Relocatable,
    ) CairoVMError!?MaybeRelocatable {
        for (self.builtin_runners.items) |*builtin_item| {
            if (builtin_item.base() == address.segment_index)
                return builtin_item.deduceMemoryCell(
                    self.allocator,
                    address,
                    self.segments.memory,
                ) catch CairoVMError.RunnerError;
        }
        return null;
    }

    /// Relocates the trace within the Cairo VM, updating relocatable registers to numbered ones.
    ///
    /// This function is responsible for relocating the trace within the Cairo VM, converting relocatable registers
    /// to their corresponding numbered ones based on the provided relocation table.
    ///
    /// # Arguments
    ///
    /// - `relocation_table`: A table containing the relocation indices for converting relocatable addresses to numbered ones.
    ///                       It maps indices representing relocatable addresses to their respective numbered ones.
    ///
    /// # Errors
    ///
    /// - Returns `TraceError.AlreadyRelocated` if the trace has already been relocated.
    /// - Returns `TraceError.NoRelocationFound` if the relocation table has insufficient entries (less than 2) to perform relocations.
    /// - Returns `TraceError.TraceNotEnabled` if the trace is not in an enabled state for relocation.
    ///
    /// # Safety
    ///
    /// This function assumes that the relocation table indices correspond correctly to the addresses
    /// needing relocation within the Cairo VM's trace.
    pub fn relocateTrace(self: *Self, relocation_table: []usize) !void {
        if (self.relocated_trace != null) return TraceError.AlreadyRelocated;
        if (relocation_table.len < 2) return TraceError.NoRelocationFound;
        if (self.trace == null) return TraceError.TraceNotEnabled;

        var relocated_trace = try std.ArrayList(RelocatedTraceEntry).initCapacity(self.allocator, self.trace.?.items.len);
        errdefer relocated_trace.deinit();

        for (self.trace.?.items) |trace|
            relocated_trace.appendAssumeCapacity(.{
                .pc = try trace.pc.relocateAddress(relocation_table),
                .ap = trace.ap + relocation_table[1],
                .fp = trace.fp + relocation_table[1],
            });

        self.relocated_trace = relocated_trace;
    }

    /// Gets the relocated trace
    /// Returns `TraceError.TraceNotRelocated` error the trace has not been relocated
    /// # Returns
    /// - `[]RelocatedTraceEntry`: an array of relocated trace.
    pub fn getRelocatedTrace(self: *Self) TraceError![]RelocatedTraceEntry {
        return if (self.relocated_trace) |rel_trace| return rel_trace.items else TraceError.TraceNotRelocated;
    }

    /// Marks a range of memory addresses as accessed within the Cairo VM's memory segment.
    ///
    /// # Arguments
    ///
    /// - `base`: The base relocatable address of the memory range to mark as accessed.
    /// - `len`: The length of the memory range to mark as accessed.
    ///
    /// # Safety
    ///
    /// - This function assumes correct usage and does not perform bounds checking. It's the responsibility of the caller
    ///   to ensure that the provided range defined by `base` and `len` is within the valid bounds of the memory segment.
    ///
    /// # Errors
    ///
    /// - Returns `CairoVMError.RunNotFinished` if the VM's run is not yet finished.
    pub fn markAddressRangeAsAccessed(self: *Self, base: Relocatable, len: usize) !void {
        if (!self.is_run_finished) return CairoVMError.RunNotFinished;
        for (0..len) |i| {
            self.segments.memory.markAsAccessed(try base.addUint(i));
        }
    }

    /// Adds a relocation rule to the Cairo VM's memory, enabling the redirection of temporary data to a specified destination.
    ///
    /// # Arguments
    ///
    /// - `src_ptr`: The source Relocatable pointer representing the temporary segment to be relocated.
    /// - `dst_ptr`: The destination Relocatable pointer where the temporary segment will be redirected.
    ///
    /// # Safety
    ///
    /// This function assumes correct usage and may result in memory relocations. It's crucial to ensure that both source and destination pointers are valid and within the boundaries of the memory segments.
    ///
    /// # Returns
    ///
    /// - This function returns an error if the relocation fails due to invalid conditions.
    pub fn addRelocationRule(
        self: *Self,
        src_ptr: Relocatable,
        dst_ptr: Relocatable,
    ) !void {
        try self.segments.memory.addRelocationRule(src_ptr, dst_ptr);
    }

    /// Retrieves the addresses of memory cells in the public memory based on segment offsets.
    ///
    /// Retrieves a list of addresses constituting the public memory. It utilizes the relocation table
    /// (`self.relocation_table`) and the `self.segments.getPublicMemoryAddresses()` method. This method
    /// ensures that the public memory addresses are retrieved based on the relocated segments.
    ///
    /// Returns a list of memory cell addresses that comprise the public memory. If the relocation table
    /// is not available, it throws `MemoryError.UnrelocatedMemory`. If an error occurs during the
    /// retrieval process, it throws `CairoVMError.Memory`.
    pub fn getPublicMemoryAddresses(self: *Self) !std.ArrayList(std.meta.Tuple(&.{ usize, usize })) {
        // Check if the relocation table is available
        if (self.relocation_table) |r| {
            // Retrieve the public memory addresses using the relocation table
            return self.segments.getPublicMemoryAddresses(&r) catch CairoVMError.Memory;
        }
        // Throw an error if the relocation table is not available
        return MemoryError.UnrelocatedMemory;
    }

    /// Loads data into the memory managed by CairoVM.
    ///
    /// This function ensures memory allocation in the CairoVM's segments, particularly in the instruction cache.
    /// It checks if the provided pointer (`ptr`) is pointing to the first segment and if the instruction cache
    /// is smaller than the incoming data. If so, it extends the instruction cache to accommodate the new data.
    ///
    /// After the cache is prepared, the function delegates the actual data loading to the segments, using the CairoVM's
    /// allocator and the provided pointer and data.
    ///
    /// # Parameters
    /// - `ptr` (Relocatable): The starting address in memory to write the data.
    /// - `data` (*std.ArrayList(MaybeRelocatable)): The data to be loaded into memory.
    ///
    /// # Returns
    /// A `Relocatable` representing the first address after the loaded data in memory.
    ///
    /// # Errors
    /// - Returns a MemoryError.Math if there's an issue with memory arithmetic during loading.
    pub fn loadData(
        self: *Self,
        ptr: Relocatable,
        data: *std.ArrayList(MaybeRelocatable),
    ) !Relocatable {
        // Check if the pointer is in the first segment and the cache needs expansion.
        if (ptr.segment_index == 0 and self.instruction_cache.items.len < data.items.len) {
            // Extend the instruction cache to match the incoming data length.
            try self.instruction_cache.appendNTimes(
                null,
                data.items.len - self.instruction_cache.items.len,
            );
        }
        // Delegate the data loading operation to the segments' loadData method and return the result.
        return self.segments.loadData(self.allocator, ptr, data.items);
    }

    /// Compares two memory segments within the Cairo VM's memory starting from specified addresses for a given length.
    ///
    /// This function provides a comparison mechanism for memory segments within the Cairo VM's memory.
    /// It compares the segments starting from the specified `lhs` (left-hand side) and `rhs`
    /// (right-hand side) addresses for a length defined by `len`.
    ///
    /// Special Cases:
    /// - If `lhs` exists in memory but `rhs` does not: returns `(Order::Greater, 0)`.
    /// - If `rhs` exists in memory but `lhs` does not: returns `(Order::Less, 0)`.
    /// - If neither `lhs` nor `rhs` exist in memory: returns `(Order::Equal, 0)`.
    ///
    /// The function behavior aligns with the C `memcmp` function for other cases,
    /// offering an optimized comparison mechanism that hints to avoid unnecessary allocations.
    ///
    /// # Arguments
    ///
    /// - `lhs`: The starting address of the left-hand memory segment.
    /// - `rhs`: The starting address of the right-hand memory segment.
    /// - `len`: The length to compare from each memory segment.
    ///
    /// # Returns
    ///
    /// Returns a tuple containing the ordering of the segments and the first relative position
    /// where they differ.
    pub fn memCmp(
        self: *Self,
        lhs: Relocatable,
        rhs: Relocatable,
        len: usize,
    ) std.meta.Tuple(&.{ std.math.Order, usize }) {
        return self.segments.memory.memCmp(lhs, rhs, len);
    }

    /// Compares memory segments for equality.
    ///
    /// Compares segments of MemoryCell items starting from the specified addresses
    /// (`lhs` and `rhs`) for a given length.
    ///
    /// # Arguments
    ///
    /// - `lhs`: The starting address of the left-hand segment.
    /// - `rhs`: The starting address of the right-hand segment.
    /// - `len`: The length to compare from each segment.
    ///
    /// # Returns
    ///
    /// Returns `true` if segments are equal up to the specified length, otherwise `false`.
    pub fn memEq(
        self: *Self,
        lhs: Relocatable,
        rhs: Relocatable,
        len: usize,
    ) !bool {
        return try self.segments.memory.memEq(lhs, rhs, len);
    }

    /// Retrieves return values from the VM's memory as a continuous range of memory values.
    ///
    /// # Arguments
    ///
    /// - `n_ret`: The number of return values to retrieve from the memory.
    ///
    /// # Returns
    ///
    /// Returns a list containing memory values retrieved as return values from the VM's memory.
    ///
    /// # Errors
    ///
    /// - Returns `MemoryError.FailedToGetReturnValues` if there's an issue retrieving the return values
    ///   from the specified memory addresses.
    pub fn getReturnValues(self: *Self, n_ret: usize) !std.ArrayList(MaybeRelocatable) {
        return self.segments.memory.getContinuousRange(
            self.allocator,
            self.run_context.getAP().subUint(n_ret) catch
                return MemoryError.FailedToGetReturnValues,
            n_ret,
        );
    }

    /// Retrieves a range of memory values starting from a specified address within the Cairo VM's memory segment.
    ///
    /// # Arguments
    ///
    /// - `address`: The starting address in the memory from which the range is retrieved.
    /// - `size`: The size of the range to be retrieved.
    ///
    /// # Returns
    ///
    /// Returns a list containing memory values retrieved from the specified range starting at the given address.
    /// The list may contain `null` elements for inaccessible memory positions.
    ///
    /// # Errors
    ///
    /// Returns an error if there are any issues encountered during the retrieval of the memory range.
    pub fn getRange(
        self: *Self,
        address: Relocatable,
        size: usize,
    ) !std.ArrayList(?MaybeRelocatable) {
        return try self.segments.memory.getRange(
            self.allocator,
            address,
            size,
        );
    }

    pub fn getRangeCheckBuiltin(
        self: *Self,
    ) CairoVMError!*RangeCheckBuiltinRunner {
        for (self.builtin_runners.items) |*runner| {
            switch (runner.*) {
                .RangeCheck => |*rc| return rc,
                else => {},
            }
        }

        return CairoVMError.NoRangeCheckBuiltin;
    }

    /// Retrieves a continuous range of memory values starting from a specified address within the Cairo VM's memory segment.
    ///
    /// # Arguments
    ///
    /// - `address`: The starting address in the memory from which the continuous range is retrieved.
    /// - `size`: The size of the continuous range to be retrieved.
    ///
    /// # Returns
    ///
    /// Returns a list containing memory values retrieved from the continuous range starting at the given address.
    ///
    /// # Errors
    ///
    /// Returns an error if there are any gaps encountered within the continuous memory range.
    pub fn getContinuousRange(
        self: *Self,
        address: Relocatable,
        size: usize,
    ) !std.ArrayList(MaybeRelocatable) {
        return try self.segments.memory.getContinuousRange(
            self.allocator,
            address,
            size,
        );
    }

    /// Performs opcode-specific assertions on the operands of an instruction.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the CairoVM instance.
    /// - `instruction`: A pointer to the instruction being asserted.
    /// - `operands`: The result of the operands computation.
    ///
    /// # Errors
    ///
    /// - Returns an error if an assertion fails.
    ///
    /// # Opcode Assertions
    ///
    /// This function performs opcode-specific assertions based on the opcode of the given instruction.
    ///
    /// - For the `AssertEq` opcode, it asserts that the result and destination operands are equal.
    ///   Returns `CairoVMError.DiffAssertValues` if the assertion fails or `CairoVMError.UnconstrainedResAssertEq`
    ///   if the result operand is unconstrained.
    ///
    /// - For the `Call` opcode, it asserts that operand 0 is the return program counter (PC) and that the destination
    ///   operand is the frame pointer (FP). Returns `CairoVMError.CantWriteReturnPc` if the assertion on operand 0 fails
    ///   or `CairoVMError.CantWriteReturnFp` if the assertion on the destination operand fails.
    ///
    /// - No assertions are performed for other opcodes.
    ///
    /// # Safety
    ///
    /// This function assumes proper initialization of the CairoVM instance and must be called in
    /// a controlled environment to ensure the correct execution of instructions and memory operations.
    pub fn opcodeAssertions(
        self: *Self,
        instruction: Instruction,
        operands: OperandsResult,
    ) !void {
        // Switch on the opcode to perform the appropriate assertion.
        switch (instruction.opcode) {
            // Assert that the result and destination operands are equal for AssertEq opcode.
            .AssertEq => {
                if (operands.res) |res| {
                    if (!res.eq(operands.dst)) {
                        return CairoVMError.DiffAssertValues;
                    }
                } else {
                    return CairoVMError.UnconstrainedResAssertEq;
                }
            },
            // Perform assertions specific to the Call opcode.
            .Call => {
                // Calculate the return program counter (PC) value.
                const return_pc = MaybeRelocatable.fromRelocatable(try self.run_context.pc.addUint(instruction.size()));
                // Assert that the operand 0 is the return PC.
                if (!operands.op_0.eq(return_pc)) {
                    return CairoVMError.CantWriteReturnPc;
                }

                // Assert that the destination operand is the frame pointer (FP).
                if (!MaybeRelocatable.fromRelocatable(self.run_context.getFP()).eq(operands.dst)) {
                    return CairoVMError.CantWriteReturnFp;
                }
            },
            // No assertions for other opcodes.
            else => {},
        }
    }

    /// Retrieves a continuous range of `Felt252` values starting from the memoryy at the specific relocatable address in the Cairo VM.
    ///
    /// This function internally calls `getFeltRange` on the memory segments manager, attempting
    /// to retrieve a range of `Felt252` values at the given address.
    ///
    /// # Arguments
    ///
    /// * `address`: The starting address in the memory from which the continuous range of `Felt252` is retrieved.
    /// * `size`: The size of the continuous range of `Felt252` to be retrieved.
    ///
    /// # Returns
    ///
    /// Returns a list containing `Felt252` values retrieved from the continuous range starting at the relocatable address.
    ///
    /// # Errors
    ///
    /// Returns an error if there are any unknown memory cell encountered within the continuous memory range.
    /// Returns an error if value inside the range is not a `Felt252`
    pub fn getFeltRange(self: *Self, address: Relocatable, size: usize) !std.ArrayList(Felt252) {
        return self.segments.memory.getFeltRange(address, size);
    }

    /// Decodes the current instruction at the program counter (PC) of the Cairo VM.
    ///
    /// # Returns
    ///
    ///  Returns the decoded instruction at the current PC.
    ///
    /// # Errors
    ///
    /// Returns an error if the instruction encoding is invalid.
    pub inline fn decodeCurrentInstruction(self: *const Self) !Instruction {
        const felt = try self.segments.memory.getFelt(self.run_context.getPC());

        const instruction = felt.toInt(u64) catch
            return CairoVMError.InvalidInstructionEncoding;

        return decoder.decodeInstructions(instruction);
    }

    /// Marks the end of the execution run in the Cairo Virtual Machine.
    ///
    /// This function finalizes the execution run by verifying auto deductions and marking the run as finished.
    /// It also checks if there is only one execution scope remaining, returning `ExecScopeError.NoScopeError` if so.
    ///
    /// Parameters:
    /// - `allocator`: The allocator to be used for any necessary memory allocations.
    /// - `exec_scopes`: Pointer to the execution scopes.
    ///
    /// Returns:
    /// - If there is only one execution scope remaining, returns `ExecScopeError.NoScopeError`.
    /// - Otherwise, returns `void`.
    ///
    /// Errors:
    /// - Returns an error if there is only one execution scope remaining (`ExecScopeError.NoScopeError`).
    pub fn endRun(self: *Self, allocator: Allocator, exec_scopes: *ExecutionScopes) !void {
        // Verify auto deductions before ending the run
        try self.verifyAutoDeductions(allocator);

        // Mark the run as finished
        self.is_run_finished = true;

        // If there is only one execution scope remaining, return immediately
        if (exec_scopes.data.items.len == 1) {
            return;
        }

        // Otherwise, return an error indicating no scope error
        return ExecScopeError.NoScopeError;
    }

    /// Writes output to the specified writer.
    ///
    /// This method writes output to the provided writer based on the output specified
    /// by the built-in runner. It iterates through the built-in runners to find the output
    /// runner, then writes the output to the writer based on the segment sizes and content.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the CairoVM instance.
    /// - `writer`: A writer to which the output is written.
    ///
    /// # Errors
    ///
    /// Returns an error if writing the output fails.
    pub fn writeOutput(self: *Self, writer: anytype) !void {
        var builtin: *BuiltinRunner = val: {

            // Iterate through the built-in runners to find the output runner.
            for (self.builtin_runners.items) |*runner| {
                if (runner.* == .Output) {
                    break :val runner;
                }
            }
            // Output runner is not exist, so we just return
            return;
        };

        // Compute effective sizes of memory segments.
        const segment_used_sizes = try self.segments.computeEffectiveSize(false);
        const segment_index = builtin.base();

        // Iterate through the memory segments and write output based on their content.
        for (0..segment_used_sizes.items[@intCast(segment_index)]) |i| {
            if (self.segments.memory.get(Relocatable.init(@intCast(segment_index), i))) |v| {
                switch (v) {
                    // Write felt value.
                    .felt => |f| std.fmt.format(writer, "{}\n", .{try f.toSignedInt(i256)}) catch
                        return CairoVMError.FailedToWriteOutput,
                    // Write relocatable value.
                    .relocatable => |r| std.fmt.format(writer, "{}:{}\n", .{ r.segment_index, r.offset }) catch
                        return CairoVMError.FailedToWriteOutput,
                }
            } else {
                // Write "<missing>" if no value is found.
                writer.writeAll("<missing>\n") catch
                    return CairoVMError.FailedToWriteOutput;
            }
        }
    }
};

/// Represents the operands for an instruction.
pub const OperandsResult = struct {
    const Self = @This();

    /// The destination operand value.
    dst: MaybeRelocatable = undefined,
    /// The result operand value.
    res: ?MaybeRelocatable = null,
    /// The first operand value.
    op_0: MaybeRelocatable = undefined,
    /// The second operand value.
    op_1: MaybeRelocatable = undefined,
    /// The relocatable address of the destination operand.
    dst_addr: Relocatable = undefined,
    /// The relocatable address of the first operand.
    op_0_addr: Relocatable = undefined,
    /// The relocatable address of the second operand.
    op_1_addr: Relocatable = undefined,
    /// Indicator for deduced operands.
    deduced_operands: u8 = 0,

    /// Sets the flag indicating the destination operand was deduced.
    ///
    /// # Arguments
    ///
    /// - `value`: A boolean value indicating whether the destination operand was deduced.
    pub inline fn setDst(self: *Self, comptime value: u8) void {
        self.deduced_operands |= value;
    }

    /// Sets the flag indicating the first operand was deduced.
    ///
    /// # Arguments
    ///
    /// - `value`: A boolean value indicating whether the first operand was deduced.
    pub inline fn setOp0(self: *Self, comptime value: u8) void {
        self.deduced_operands |= (value << 1);
    }

    /// Sets the flag indicating the second operand was deduced.
    ///
    /// # Arguments
    ///
    /// - `value`: A boolean value indicating whether the second operand was deduced.
    pub inline fn setOp1(self: *Self, comptime value: u8) void {
        self.deduced_operands |= (value << 2);
    }

    /// Checks if the destination operand was deduced.
    ///
    /// # Returns
    ///
    /// - A boolean indicating if the destination operand was deduced.
    pub inline fn wasDestDeducted(self: *const Self) bool {
        return self.deduced_operands & 1 != 0;
    }

    /// Checks if the first operand was deduced.
    ///
    /// # Returns
    ///
    /// - A boolean indicating if the first operand was deduced.
    pub inline fn wasOp0Deducted(self: *const Self) bool {
        return self.deduced_operands & (1 << 1) != 0;
    }

    /// Checks if the second operand was deduced.
    ///
    /// # Returns
    ///
    /// - A boolean indicating if the second operand was deduced.
    pub inline fn wasOp1Deducted(self: *const Self) bool {
        return self.deduced_operands & (1 << 2) != 0;
    }
};
