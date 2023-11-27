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
const Config = @import("config.zig").Config;
const TraceContext = @import("trace_context.zig").TraceContext;
const build_options = @import("../build_options.zig");
const BuiltinRunner = @import("./builtins/builtin_runner/builtin_runner.zig").BuiltinRunner;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HashBuiltinRunner = @import("./builtins/builtin_runner/hash.zig").HashBuiltinRunner;
const Instruction = instructions.Instruction;

/// Represents the Cairo VM.
pub const CairoVM = struct {
    const Self = @This();

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************

    /// The memory allocator. Can be needed for the deallocation of the VM resources.
    allocator: Allocator,
    /// The run context.
    run_context: *RunContext,
    /// ArrayList of built-in runners
    builtin_runners: ArrayList(BuiltinRunner),
    /// The memory segment manager.
    segments: *segments.MemorySegmentManager,
    /// Whether the run is finished or not.
    is_run_finished: bool,
    /// VM trace
    trace_context: TraceContext,
    /// Current Step
    current_step: usize,
    /// Rc limits
    rc_limits: ?struct { i16, i16 },

    // ************************************************************
    // *             MEMORY ALLOCATION AND DEALLOCATION           *
    // ************************************************************

    /// Creates a new Cairo VM.
    /// # Arguments
    /// - `allocator`: The allocator to use for the VM.
    /// - `config`: Configurations used to initialize the VM.
    /// # Returns
    /// - `CairoVM`: The created VM.
    /// # Errors
    /// - If a memory allocation fails.
    pub fn init(
        allocator: Allocator,
        config: Config,
    ) !Self {
        // Initialize the memory segment manager.
        const memory_segment_manager = try segments.MemorySegmentManager.init(allocator);
        errdefer memory_segment_manager.deinit();
        // Initialize the run context.
        const run_context = try RunContext.init(allocator);
        errdefer run_context.deinit();
        // Initialize the trace context.
        const trace_context = try TraceContext.init(allocator, config.enable_trace);
        errdefer trace_context.deinit();
        // Initialize the built-in runners.
        const builtin_runners = ArrayList(BuiltinRunner).init(allocator);
        errdefer builtin_runners.deinit();

        return Self{
            .allocator = allocator,
            .run_context = run_context,
            .builtin_runners = builtin_runners,
            .segments = memory_segment_manager,
            .is_run_finished = false,
            .trace_context = trace_context,
            .current_step = 0,
            .rc_limits = null,
        };
    }

    /// Safe deallocation of the VM resources.
    pub fn deinit(self: *Self) void {
        // Deallocate the memory segment manager.
        self.segments.deinit();
        // Deallocate the run context.
        self.run_context.deinit();
        // Deallocate trace
        self.trace_context.deinit();
        // Deallocate built-in runners
        self.builtin_runners.deinit();
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
    pub fn computeSegmentsEffectiveSizes(self: *Self, allow_temp_segments: bool) !std.AutoArrayHashMap(i64, u32) {
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
    ) error{MemoryOutOfBounds}!?MaybeRelocatable {
        return self.segments.memory.get(address);
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

    pub fn insertInMemory(
        self: *Self,
        address: Relocatable,
        value: MaybeRelocatable,
    ) error{ InvalidMemoryAddress, MemoryOutOfBounds }!void {
        _ = value;
        _ = address;
        _ = self;

        // TODO: complete the implementation once set method is completed in Memory
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
    pub fn getSegmentUsedSize(self: *Self, index: u32) ?u32 {
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
    pub fn getSegmentSize(self: *Self, index: u32) ?u32 {
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

    /// Do a single step of the VM.
    /// Process an instruction cycle using the typical fetch-decode-execute cycle.
    pub fn step(self: *Self, allocator: Allocator) !void {
        // TODO: Run hints.

        std.log.debug(
            "Running instruction at pc: {}",
            .{self.run_context.pc.*},
        );

        // ************************************************************
        // *                    FETCH                                 *
        // ************************************************************

        const encoded_instruction = self.segments.memory.get(self.run_context.pc.*) catch {
            return CairoVMError.InstructionFetchingFailed;
        };

        // ************************************************************
        // *                    DECODE                                *
        // ************************************************************

        // First, we convert the encoded instruction to a u64.
        // If the MaybeRelocatable is not a felt, this operation will fail.
        // If the MaybeRelocatable is a felt but the value does not fit into a u64, this operation will fail.
        const encoded_instruction_u64 = encoded_instruction.?.tryIntoU64() catch {
            return CairoVMError.InstructionEncodingError;
        };

        // Then, we decode the instruction.
        const instruction = try instructions.decode(encoded_instruction_u64);

        // ************************************************************
        // *                    EXECUTE                               *
        // ************************************************************
        return self.runInstruction(allocator, &instruction);
    }

    /// Insert Operands only after checking if they were deduced.
    // # Arguments
    /// - `allocator`: allocator where OperandsResult stored.
    /// - `op`: OperandsResult object that stores all operands.
    pub fn insertDeducedOperands(self: *Self, allocator: Allocator, op: OperandsResult) !void {
        if (op.wasOp0Deducted()) {
            try self.segments.memory.set(allocator, op.op_0_addr, op.op_0);
        }
        if (op.wasOp1Deducted()) {
            try self.segments.memory.set(allocator, op.op_1_addr, op.op_1);
        }
        if (op.wasDestDeducted()) {
            try self.segments.memory.set(allocator, op.dst_addr, op.dst);
        }
    }

    /// Run a specific instruction.
    // # Arguments
    /// - `instruction`: The instruction to run.
    pub fn runInstruction(
        self: *Self,
        allocator: Allocator,
        instruction: *const instructions.Instruction,
    ) !void {
        if (!build_options.trace_disable) {
            try self.trace_context.traceInstruction(.{
                .pc = self.run_context.pc,
                .ap = self.run_context.ap,
                .fp = self.run_context.fp,
            });
        }

        const operands_result = try self.computeOperands(allocator, instruction);
        try self.insertDeducedOperands(allocator, operands_result);

        try self.updateRegisters(
            instruction,
            operands_result,
        );

        const OFFSET_BITS: u32 = 16;
        const off_0 = instruction.off_0 + (@as(i16, 1) << (OFFSET_BITS - 1));
        const off_1 = instruction.off_1 + (@as(i16, 1) << (OFFSET_BITS - 1));
        const off_2 = instruction.off_2 + (@as(i16, 1) << (OFFSET_BITS - 1));

        const limits = self.rc_limits orelse .{ off_0, off_0 };
        self.rc_limits = .{ @min(limits[0], off_0, off_1, off_2), @max(limits[1], off_0, off_1, off_2) };

        self.segments.memory.markAsAccessed(operands_result.dst_addr);
        self.segments.memory.markAsAccessed(operands_result.op_0_addr);
        self.segments.memory.markAsAccessed(operands_result.op_1_addr);

        self.current_step += 1;
    }

    /// Compute the operands for a given instruction.
    /// # Arguments
    /// - `instruction`: The instruction to compute the operands for.
    /// # Returns
    /// - `Operands`: The operands for the instruction.
    pub fn computeOperands(
        self: *Self,
        allocator: Allocator,
        instruction: *const instructions.Instruction,
    ) !OperandsResult {
        var op_res = OperandsResult.default();

        op_res.res = null;

        op_res.dst_addr = try self.run_context.computeDstAddr(instruction);
        const dst_op = try self.segments.memory.get(op_res.dst_addr);

        op_res.op_0_addr = try self.run_context.computeOp0Addr(instruction);

        op_res.op_1_addr = try self.run_context.computeOp1Addr(
            instruction,
            op_res.op_0,
        );
        const op_1_op = try self.segments.memory.get(op_res.op_1_addr);

        // Deduce the operands if they haven't been successfully retrieved from memory.

        if (self.segments.memory.get(op_res.op_0_addr) catch null) |op_0| {
            op_res.op_0 = op_0;
        } else {
            op_res.setOp0(true);
            op_res.op_0 = try self.computeOp0Deductions(
                allocator,
                op_res.op_0_addr,
                instruction,
                &dst_op,
                &op_1_op,
            );
        }

        if (op_1_op) |op_1| {
            op_res.op_1 = op_1;
        } else {
            op_res.setOp1(true);
            op_res.op_1 = try self.computeOp1Deductions(
                allocator,
                op_res.op_1_addr,
                &op_res.res,
                instruction,
                &dst_op,
                &@as(?MaybeRelocatable, op_res.op_0),
            );
        }

        if (op_res.res == null) {
            op_res.res = try computeRes(instruction, op_res.op_0, op_res.op_1);
        }

        if (dst_op) |dst| {
            op_res.dst = dst;
        } else {
            op_res.setDst(true);
            op_res.dst = try self.deduceDst(instruction, op_res.res);
        }

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
    pub fn computeOp0Deductions(
        self: *Self,
        allocator: Allocator,
        op_0_addr: Relocatable,
        instruction: *const instructions.Instruction,
        dst: *const ?MaybeRelocatable,
        op1: *const ?MaybeRelocatable,
    ) !MaybeRelocatable {
        const op0_op = try self.deduceMemoryCell(allocator, op_0_addr) orelse (try self.deduceOp0(
            instruction,
            dst,
            op1,
        )).op_0;

        return op0_op orelse CairoVMError.FailedToComputeOp0;
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
    pub fn computeOp1Deductions(
        self: *Self,
        allocator: Allocator,
        op1_addr: Relocatable,
        res: *?MaybeRelocatable,
        instruction: *const instructions.Instruction,
        dst_op: *const ?MaybeRelocatable,
        op0: *const ?MaybeRelocatable,
    ) !MaybeRelocatable {
        if (try self.deduceMemoryCell(allocator, op1_addr)) |op1| {
            return op1;
        } else {
            const op1_deductions = try deduceOp1(instruction, dst_op, op0);
            if (res.* == null) {
                res.* = op1_deductions.res;
            }
            return op1_deductions.op_1 orelse return CairoVMError.FailedToComputeOp1;
        }
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
        self: *Self,
        inst: *const instructions.Instruction,
        dst: *const ?MaybeRelocatable,
        op1: *const ?MaybeRelocatable,
    ) !Op0Result {
        switch (inst.opcode) {
            .Call => {
                return .{
                    .op_0 = MaybeRelocatable.fromRelocatable(try self.run_context.pc.addUint(inst.size())),
                    .res = null,
                };
            },
            .AssertEq => {
                const dst_val = dst.* orelse return .{ .op_0 = null, .res = null };
                const op1_val = op1.* orelse return .{ .op_0 = null, .res = null };
                if ((inst.res_logic == .Add)) {
                    return .{
                        .op_0 = try subOperands(dst_val, op1_val),
                        .res = dst_val,
                    };
                } else if (dst_val.isFelt() and op1_val.isFelt() and !op1_val.felt.isZero()) {
                    return .{
                        .op_0 = MaybeRelocatable.fromFelt(try dst_val.felt.div(op1_val.felt)),
                        .res = dst_val,
                    };
                }
            },
            else => {
                return .{ .op_0 = null, .res = null };
            },
        }
        return .{ .op_0 = null, .res = null };
    }

    /// Updates the value of PC according to the executed instruction.
    /// # Arguments
    /// - `instruction`: The instruction that was executed.
    /// - `operands`: The operands of the instruction.
    pub fn updatePc(
        self: *Self,
        instruction: *const instructions.Instruction,
        operands: OperandsResult,
    ) !void {
        switch (instruction.pc_update) {
            // PC update regular
            .Regular => { // Update the PC.
                self.run_context.pc.*.addUintInPlace(instruction.size());
            },
            // PC update jump
            .Jump => {
                // Check that the res is not null.
                if (operands.res) |val| {
                    // Check that the res is a relocatable.
                    self.run_context.pc.* = val.tryIntoRelocatable() catch
                        return error.PcUpdateJumpResNotRelocatable;
                } else {
                    return error.ResUnconstrainedUsedWithPcUpdateJump;
                }
            },
            // PC update Jump Rel
            .JumpRel => {
                // Check that the res is not null.
                if (operands.res) |val| {
                    // Check that the res is a felt.
                    try self.run_context.pc.*.addFeltInPlace(val.tryIntoFelt() catch return error.PcUpdateJumpRelResNotFelt);
                } else {
                    return error.ResUnconstrainedUsedWithPcUpdateJumpRel;
                }
            },
            // PC update Jnz
            .Jnz => {
                if (operands.dst.isZero()) {
                    // Update the PC.
                    self.run_context.pc.*.addUintInPlace(instruction.size());
                } else {
                    // Update the PC.
                    try self.run_context.pc.*.addMaybeRelocatableInplace(operands.op_1);
                }
            },
        }
    }

    /// Updates the value of AP according to the executed instruction.
    /// # Arguments
    /// - `instruction`: The instruction that was executed.
    /// - `operands`: The operands of the instruction.
    pub fn updateAp(
        self: *Self,
        instruction: *const instructions.Instruction,
        operands: OperandsResult,
    ) !void {
        switch (instruction.ap_update) {
            // AP update Add
            .Add => {
                // Check that Res is not null.
                if (operands.res) |val| {
                    // Update AP.
                    try self.run_context.ap.*.addMaybeRelocatableInplace(val);
                } else {
                    return error.ApUpdateAddResUnconstrained;
                }
            },
            // AP update Add1
            .Add1 => {
                self.run_context.ap.*.addUintInPlace(1);
            },
            // AP update Add2
            .Add2 => {
                self.run_context.ap.*.addUintInPlace(2);
            },
            // AP update regular
            .Regular => {},
        }
    }

    /// Updates the value of AP according to the executed instruction.
    /// # Arguments
    /// - `instruction`: The instruction that was executed.
    /// - `operands`: The operands of the instruction.
    pub fn updateFp(
        self: *Self,
        instruction: *const instructions.Instruction,
        operands: OperandsResult,
    ) !void {
        switch (instruction.fp_update) {
            // FP update Add + 2
            instructions.FpUpdate.APPlus2 => { // Update the FP.
                // FP = AP + 2.
                self.run_context.fp.*.offset = self.run_context.ap.*.offset + 2;
            },
            // FP update Dst
            instructions.FpUpdate.Dst => {
                switch (operands.dst) {
                    .relocatable => |rel| {
                        // Update the FP.
                        // FP = DST.
                        self.run_context.fp.* = rel;
                    },
                    .felt => |f| {
                        // Update the FP.
                        // FP += DST.
                        try self.run_context.fp.*.addFeltInPlace(f);
                    },
                }
            },
            else => {},
        }
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
    pub fn updateRegisters(
        self: *Self,
        instruction: *const instructions.Instruction,
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
        self: *Self,
        instruction: *const Instruction,
        res: ?MaybeRelocatable,
    ) !MaybeRelocatable {
        return switch (instruction.opcode) {
            .AssertEq => {
                if (res != null) {
                    return res.?;
                } else {
                    return CairoVMError.NoDst;
                }
            },
            .Call => MaybeRelocatable.fromRelocatable(self.run_context.fp.*),
            else => CairoVMError.NoDst,
        };
    }

    // ************************************************************
    // *                    ACCESSORS                             *
    // ************************************************************

    /// Returns whether the run is finished or not.
    /// # Returns
    /// - `bool`: Whether the run is finished or not.
    pub fn isRunFinished(self: *const Self) bool {
        return self.is_run_finished;
    }

    /// Applies the corresponding builtin's deduction rules if addr's segment index corresponds to a builtin segment
    /// Returns null if there is no deduction for the address
    /// # Arguments
    /// - `address`: The address to deduce.
    /// # Returns
    /// - `MaybeRelocatable`: The deduced value.
    pub fn deduceMemoryCell(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
    ) CairoVMError!?MaybeRelocatable {
        for (self.builtin_runners.items) |builtin_item| {
            if (@as(
                u64,
                @intCast(builtin_item.base()),
            ) == address.segment_index) {
                return builtin_item.deduceMemoryCell(
                    allocator,
                    address,
                    self.segments.memory,
                ) catch {
                    return CairoVMError.RunnerError;
                };
            }
        }
        return null;
    }
};

/// Compute the result operand for a given instruction on op 0 and op 1.
/// # Arguments
/// - `instruction`: The instruction to compute the operands for.
/// - `op_0`: The operand 0.
/// - `op_1`: The operand 1.
/// # Returns
/// - `res`: The result of the operation.
pub fn computeRes(
    instruction: *const Instruction,
    op_0: MaybeRelocatable,
    op_1: MaybeRelocatable,
) !?MaybeRelocatable {
    return switch (instruction.res_logic) {
        .Op1 => op_1,
        .Add => return try addOperands(op_0, op_1),
        .Mul => return try mulOperands(op_0, op_1),
        .Unconstrained => null,
    };
}

/// Add two operands which can either be a "relocatable" or a "felt".
/// The operation is allowed between:
/// 1. A felt and another felt.
/// 2. A felt and a relocatable.
/// Adding two relocatables is forbidden.
/// # Arguments
/// - `op_0`: The operand 0.
/// - `op_1`: The operand 1.
/// # Returns
/// - `MaybeRelocatable`: The result of the operation or an error.
pub fn addOperands(
    op_0: MaybeRelocatable,
    op_1: MaybeRelocatable,
) !MaybeRelocatable {
    // Both operands are relocatables, operation forbidden
    if (op_0.isRelocatable() and op_1.isRelocatable()) {
        return error.AddRelocToRelocForbidden;
    }

    // One of the operands is relocatable, the other is felt
    if (op_0.isRelocatable() or op_1.isRelocatable()) {
        // Determine which operand is relocatable and which one is felt
        const reloc_op = if (op_0.isRelocatable()) op_0 else op_1;
        const felt_op = if (op_0.isRelocatable()) op_1 else op_0;

        var reloc = try reloc_op.tryIntoRelocatable();

        // Add the felt to the relocatable's offset
        try reloc.addFeltInPlace(try felt_op.tryIntoFelt());

        return MaybeRelocatable.fromRelocatable(reloc);
    }

    // Add the felts and return as a new felt wrapped in a relocatable
    return MaybeRelocatable.fromFelt((try op_0.tryIntoFelt()).add(
        try op_1.tryIntoFelt(),
    ));
}

/// Compute the product of two operands op 0 and op 1.
/// # Arguments
/// - `op_0`: The operand 0.
/// - `op_1`: The operand 1.
/// # Returns
/// - `MaybeRelocatable`: The result of the operation or an error.
pub fn mulOperands(
    op_0: MaybeRelocatable,
    op_1: MaybeRelocatable,
) CairoVMError!MaybeRelocatable {
    // At least one of the operands is relocatable
    if (op_0.isRelocatable() or op_1.isRelocatable()) {
        return CairoVMError.MulRelocForbidden;
    }

    // Multiply the felts and return as a new felt wrapped in a relocatable
    return MaybeRelocatable.fromFelt(
        (try op_0.tryIntoFelt()).mul(try op_1.tryIntoFelt()),
    );
}

/// Subtracts a `MaybeRelocatable` from this one and returns the new value.
///
/// Only values of the same type may be subtracted. Specifically, attempting to
/// subtract a `.felt` with a `.relocatable` will result in an error.
pub fn subOperands(self: MaybeRelocatable, other: MaybeRelocatable) !MaybeRelocatable {
    switch (self) {
        .felt => |self_value| switch (other) {
            .felt => |other_value| return MaybeRelocatable.fromFelt(
                self_value.sub(other_value),
            ),
            .relocatable => return error.TypeMismatchNotFelt,
        },
        .relocatable => |self_value| switch (other) {
            .felt => return error.TypeMismatchNotFelt,
            .relocatable => |other_value| return MaybeRelocatable.fromRelocatable(
                try self_value.sub(other_value),
            ),
        },
    }
}

/// Attempts to deduce `op1` and `res` for an instruction, given `dst` and `op0`.
///
/// # Arguments
/// - `inst`: The instruction to deduce `op1` and `res` for.
/// - `dst`: The destination of the instruction.
/// - `op0`: The first operand of the instruction.
///
/// # Returns
/// - `Tuple`: A tuple containing the deduced `op1` and `res`.
pub fn deduceOp1(
    inst: *const instructions.Instruction,
    dst: *const ?MaybeRelocatable,
    op0: *const ?MaybeRelocatable,
) !Op1Result {
    if (inst.opcode != .AssertEq) {
        return .{ .op_1 = null, .res = null };
    }

    switch (inst.res_logic) {
        .Op1 => if (dst.*) |dst_val| {
            return .{ .op_1 = dst_val, .res = dst_val };
        },
        .Add => if (dst.* != null and op0.* != null) {
            return .{
                .op_1 = try subOperands(dst.*.?, op0.*.?),
                .res = dst.*.?,
            };
        },
        .Mul => {
            if (dst.* != null and op0.* != null and dst.*.?.isFelt() and op0.*.?.isFelt() and !op0.*.?.felt.isZero()) {
                return .{
                    .op_1 = MaybeRelocatable.fromFelt(try dst.*.?.felt.div(op0.*.?.felt)),
                    .res = dst.*.?,
                };
            }
        },
        else => {},
    }

    return .{ .op_1 = null, .res = null };
}

// *****************************************************************************
// *                       CUSTOM TYPES                                        *
// *****************************************************************************

/// Represents the operands for an instruction.
pub const OperandsResult = struct {
    const Self = @This();

    dst: MaybeRelocatable,
    res: ?MaybeRelocatable,
    op_0: MaybeRelocatable,
    op_1: MaybeRelocatable,
    dst_addr: Relocatable,
    op_0_addr: Relocatable,
    op_1_addr: Relocatable,
    deduced_operands: u8,

    /// Returns a default instance of the OperandsResult struct.
    pub fn default() Self {
        return .{
            .dst = MaybeRelocatable.fromU64(0),
            .res = MaybeRelocatable.fromU64(0),
            .op_0 = MaybeRelocatable.fromU64(0),
            .op_1 = MaybeRelocatable.fromU64(0),
            .dst_addr = .{},
            .op_0_addr = .{},
            .op_1_addr = .{},
            .deduced_operands = 0,
        };
    }

    pub fn setDst(self: *Self, value: bool) void {
        self.deduced_operands |= if (value) 1 else 0;
    }
    pub fn setOp0(self: *Self, value: bool) void {
        self.deduced_operands |= if (value) 1 << 1 else 0 << 1;
    }

    pub fn setOp1(self: *Self, value: bool) void {
        self.deduced_operands |= if (value) 1 << 2 else 0 << 2;
    }
    pub fn wasDestDeducted(self: *const Self) bool {
        return self.deduced_operands & 1 != 0;
    }

    pub fn wasOp0Deducted(self: *const Self) bool {
        return self.deduced_operands & (1 << 1) != 0;
    }

    pub fn wasOp1Deducted(self: *const Self) bool {
        return self.deduced_operands & (1 << 2) != 0;
    }
};

/// Represents the result of deduce Op0 operation.
const Op0Result = struct {
    const Self = @This();
    /// The computed operand Op0.
    op_0: ?MaybeRelocatable,
    /// The result of the operation involving Op0.
    res: ?MaybeRelocatable,
};

/// Represents the result of deduce Op1 operation.
const Op1Result = struct {
    const Self = @This();
    /// The computed operand Op1.
    op_1: ?MaybeRelocatable,
    /// The result of the operation involving Op1.
    res: ?MaybeRelocatable,
};
