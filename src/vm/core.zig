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
const builtin = @import("./builtins/bitwise/bitwise.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HashBuiltinRunner = @import("./builtins/builtin_runner/hash.zig").HashBuiltinRunner;
const Instruction = @import("instructions.zig").Instruction;

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

    /// Do a single step of the VM.
    /// Process an instruction cycle using the typical fetch-decode-execute cycle.
    pub fn step(self: *Self) !void {
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
        const encoded_instruction_u64 = encoded_instruction.tryIntoU64() catch {
            return CairoVMError.InstructionEncodingError;
        };

        // Then, we decode the instruction.
        const instruction = try instructions.decode(encoded_instruction_u64);

        // ************************************************************
        // *                    EXECUTE                               *
        // ************************************************************
        return self.runInstruction(&instruction);
    }

    /// Run a specific instruction.
    // # Arguments
    /// - `instruction`: The instruction to run.
    pub fn runInstruction(
        self: *Self,
        instruction: *const instructions.Instruction,
    ) !void {
        if (!build_options.trace_disable) {
            try self.trace_context.traceInstruction(.{
                .pc = self.run_context.pc,
                .ap = self.run_context.ap,
                .fp = self.run_context.fp,
            });
        }

        const operands_result = try self.computeOperands(instruction);
        _ = operands_result;
    }

    /// Compute the operands for a given instruction.
    /// # Arguments
    /// - `instruction`: The instruction to compute the operands for.
    /// # Returns
    /// - `Operands`: The operands for the instruction.
    pub fn computeOperands(
        self: *Self,
        instruction: *const instructions.Instruction,
    ) !OperandsResult {
        // Compute the destination address and get value from the memory.
        const dst_addr = try self.run_context.compute_dst_addr(instruction);
        const dst = try self.segments.memory.get(dst_addr);

        // Compute the OP 0 address and get value from the memory.
        const op_0_addr = try self.run_context.compute_op_0_addr(instruction);
        // Here we use `catch null` because we want op_0_op to be optional since it's not always used.
        // TODO: identify if we need to use try or catch here.
        const op_0_op = try self.segments.memory.get(op_0_addr);

        // Compute the OP 1 address and get value from the memory.
        const op_1_addr = try self.run_context.compute_op_1_addr(
            instruction,
            op_0_op,
        );
        const op_1_op = try self.segments.memory.get(op_1_addr);

        const res = try computeRes(instruction, op_0_op, op_1_op);

        // Deduce the operands if they haven't been successfully retrieved from memory.
        // TODO: Implement this.

        return .{
            .dst = dst,
            .res = res,
            .op_0 = op_0_op,
            .op_1 = op_1_op,
            .dst_addr = dst_addr,
            .op_0_addr = op_0_addr,
            .op_1_addr = op_1_addr,
        };
    }

    /// Runs deductions for Op0, first runs builtin deductions, if this fails, attempts to deduce it based on dst and op1
    /// Also returns res if it was also deduced in the process
    /// Inserts the deduced operand
    /// Fails if Op0 was not deduced or if an error arose in the process.
    /// # Arguments
    /// - `op_0_addr`: The address of the operand to deduce.
    /// - `instruction`: The instruction to deduce the operand for.
    /// - `dst`: The destination.
    /// - `op1`: The op1.
    pub fn computeOp0Deductions(
        self: *Self,
        op_0_addr: MaybeRelocatable,
        instruction: *const instructions.Instruction,
        dst: ?MaybeRelocatable,
        op1: ?MaybeRelocatable,
    ) void {
        _ = op1;
        _ = dst;
        _ = instruction;
        const op_o = try self.deduceMemoryCell(op_0_addr);
        _ = op_o;
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
        dst: ?*const MaybeRelocatable,
        op1: ?*const MaybeRelocatable,
    ) !std.meta.Tuple(&.{ ?relocatable.MaybeRelocatable, ?relocatable.MaybeRelocatable }) {
        switch (inst.opcode) {
            .Call => {
                return .{ relocatable.newFromRelocatable(try self.run_context.pc.addUint(inst.size())), null };
            },
            .AssertEq => {
                const dst_val = dst orelse return .{ null, null };
                const op1_val = op1 orelse return .{ null, null };
                if ((inst.res_logic == .Add)) {
                    return .{ try subOperands(dst_val.*, op1_val.*), dst_val.* };
                } else if (dst_val.isFelt() and op1_val.isFelt() and
                    !op1_val.felt.isZero())
                {
                    return .{
                        relocatable.fromFelt(try dst_val.felt.div(op1_val.felt)),
                        dst_val.*,
                    };
                }
            },
            else => {
                return .{ null, null };
            },
        }
        return .{ null, null };
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
            instructions.PcUpdate.Regular =>
            // Update the PC.
            self.run_context.pc.*.addUintInPlace(instruction.size()),
            // PC update jump
            instructions.PcUpdate.Jump => {
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
            instructions.PcUpdate.JumpRel => {
                // Check that the res is not null.
                if (operands.res) |val| {
                    // Check that the res is a felt.
                    try self.run_context.pc.*.addFeltInPlace(val.tryIntoFelt() catch return error.PcUpdateJumpRelResNotFelt);
                } else {
                    return error.ResUnconstrainedUsedWithPcUpdateJumpRel;
                }
            },
            // PC update Jnz
            instructions.PcUpdate.Jnz => {
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
            instructions.ApUpdate.Add => {
                // Check that Res is not null.
                if (operands.res) |val| {
                    // Update AP.
                    try self.run_context.ap.*.addMaybeRelocatableInplace(val);
                } else {
                    return error.ApUpdateAddResUnconstrained;
                }
            },
            // AP update Add1
            instructions.ApUpdate.Add1 => {
                self.run_context.ap.*.addUintInPlace(1);
            },
            // AP update Add2
            instructions.ApUpdate.Add2 => {
                self.run_context.ap.*.addUintInPlace(2);
            },
            else => {},
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
            instructions.FpUpdate.APPlus2 =>
            // Update the FP.
            // FP = AP + 2.
            self.run_context.fp.*.offset = self.run_context.ap.*.offset + 2,
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

    // ************************************************************
    // *                    ACCESSORS                             *
    // ************************************************************

    /// Returns whether the run is finished or not.
    /// # Returns
    /// - `bool`: Whether the run is finished or not.
    pub fn isRunFinished(self: *const Self) bool {
        return self.is_run_finished;
    }

    /// Returns the current ap.
    /// # Returns
    /// - `MaybeRelocatable`: The current ap.
    pub fn getAp(self: *const Self) Relocatable {
        return self.run_context.ap.*;
    }

    /// Returns the current fp.
    /// # Returns
    /// - `MaybeRelocatable`: The current fp.
    pub fn getFp(self: *const Self) Relocatable {
        return self.run_context.fp.*;
    }

    /// Returns the current pc.
    /// # Returns
    /// - `MaybeRelocatable`: The current pc.
    pub fn getPc(self: *const Self) Relocatable {
        return self.run_context.pc.*;
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
        for (self.builtin_runners.items) |builtin_item| {
            if (@as(
                u64,
                @intCast(builtin_item.base()),
            ) == address.segment_index) {
                return builtin.deduce(
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
) CairoVMError!?MaybeRelocatable {
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
) CairoVMError!MaybeRelocatable {
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

        return relocatable.newFromRelocatable(reloc);
    }

    // Add the felts and return as a new felt wrapped in a relocatable
    return relocatable.fromFelt((try op_0.tryIntoFelt()).add(
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
    return relocatable.fromFelt(
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
            .felt => |other_value| return relocatable.fromFelt(
                self_value.sub(other_value),
            ),
            .relocatable => return error.TypeMismatchNotFelt,
        },
        .relocatable => |self_value| switch (other) {
            .felt => return error.TypeMismatchNotFelt,
            .relocatable => |other_value| return relocatable.newFromRelocatable(
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
    dst: ?*const MaybeRelocatable,
    op0: ?*const MaybeRelocatable,
) !std.meta.Tuple(&[_]type{ ?relocatable.MaybeRelocatable, ?relocatable.MaybeRelocatable }) {
    if (inst.opcode != .AssertEq) {
        return .{ null, null };
    }

    switch (inst.res_logic) {
        .Op1 => if (dst) |dst_val| {
            return .{ dst_val.*, dst_val.* };
        },
        .Add => if (dst != null and op0 != null) {
            return .{ try subOperands(
                dst.?.*,
                op0.?.*,
            ), dst.?.* };
        },
        .Mul => {
            if (dst != null and op0 != null and
                dst.?.isFelt() and op0.?.isFelt() and
                !op0.?.felt.isZero())
            {
                return .{
                    relocatable.fromFelt(
                        try dst.?.felt.div(op0.?.felt),
                    ),
                    dst.?.*,
                };
            }
        },
        else => {},
    }

    return .{ null, null };
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

    /// Returns a default instance of the OperandsResult struct.
    pub fn default() Self {
        return .{
            .dst = relocatable.fromU64(0),
            .res = relocatable.fromU64(0),
            .op_0 = relocatable.fromU64(0),
            .op_1 = relocatable.fromU64(0),
            .dst_addr = .{},
            .op_0_addr = .{},
            .op_1_addr = .{},
        };
    }
};

const Op0Result = struct {
    op_0: MaybeRelocatable,
    res: MaybeRelocatable,
};
