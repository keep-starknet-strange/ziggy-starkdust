// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const starknet_felt = @import("../math/fields/starknet.zig");

// Local imports.
const segments = @import("memory/segments.zig");
const relocatable = @import("memory/relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const instructions = @import("instructions.zig");
const RunContext = @import("run_context.zig").RunContext;
const CairoVMError = @import("error.zig").CairoVMError;
const Config = @import("config.zig").Config;
const TraceContext = @import("trace_context.zig").TraceContext;
const build_options = @import("../build_options.zig");
const Instruction = @import("instructions.zig").Instruction;

/// Represents the Cairo VM.
pub const CairoVM = struct {

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************

    /// The memory allocator. Can be needed for the deallocation of the VM resources.
    allocator: Allocator,
    /// The run context.
    run_context: *RunContext,
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
    ) !CairoVM {
        // Initialize the memory segment manager.
        const memory_segment_manager = try segments.MemorySegmentManager.init(allocator);
        // Initialize the run context.
        const run_context = try RunContext.init(allocator);
        // Initialize the trace context.
        const trace_context = try TraceContext.init(allocator, config.enable_trace);

        return CairoVM{
            .allocator = allocator,
            .run_context = run_context,
            .segments = memory_segment_manager,
            .is_run_finished = false,
            .trace_context = trace_context,
        };
    }

    /// Safe deallocation of the VM resources.
    pub fn deinit(self: *CairoVM) void {
        // Deallocate the memory segment manager.
        self.segments.deinit();
        // Deallocate the run context.
        self.run_context.deinit();
        // Deallocate trace
        self.trace_context.deinit();
    }

    // ************************************************************
    // *                        METHODS                           *
    // ************************************************************

    /// Do a single step of the VM.
    /// Process an instruction cycle using the typical fetch-decode-execute cycle.
    pub fn step(self: *CairoVM) !void {
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
        self: *CairoVM,
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
        self: *CairoVM,
        instruction: *const instructions.Instruction,
    ) !OperandsResult {
        // Compute the destination address and get value from the memory.
        const dst_addr = try self.run_context.compute_dst_addr(instruction);
        const dst = try self.segments.memory.get(dst_addr);

        // Compute the OP 0 address and get value from the memory.
        const op_0_addr = try self.run_context.compute_op_0_addr(instruction);
        // Here we use `catch null` because we want op_0_op to be optional since it's not always used.
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

        return OperandsResult{
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
        self: *CairoVM,
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

    /// Applies the corresponding builtin's deduction rules if addr's segment index corresponds to a builtin segment
    /// Returns null if there is no deduction for the address
    /// # Arguments
    /// - `address`: The address to deduce.
    /// # Returns
    /// - `MaybeRelocatable`: The deduced value.
    /// TODO: Implement this.
    pub fn deduceMemoryCell(
        self: *CairoVM,
        address: relocatable.Relocatable,
    ) !?MaybeRelocatable {
        _ = address;
        _ = self;
        return null;
    }

    /// Updates the value of PC according to the executed instruction.
    /// # Arguments
    /// - `instruction`: The instruction that was executed.
    /// - `operands`: The operands of the instruction.
    pub fn updatePc(
        self: *CairoVM,
        instruction: *const instructions.Instruction,
        operands: OperandsResult,
    ) !void {
        switch (instruction.pc_update) {
            // ************************************************************
            // *                PC UPDATE REGULAR                         *
            // ************************************************************
            instructions.PcUpdate.Regular => {
                // Update the PC.
                self.run_context.pc.*.addUintInPlace(instruction.size());
            },
            // ************************************************************
            // *                PC UPDATE JUMP                            *
            // ************************************************************
            instructions.PcUpdate.Jump => {
                // Check that the res is not null.
                if (operands.res == null) {
                    return error.ResUnconstrainedUsedWithPcUpdateJump;
                }
                // Check that the res is a relocatable.
                const res = operands.res.?.tryIntoRelocatable() catch {
                    return error.PcUpdateJumpResNotRelocatable;
                };
                // Update the PC.
                self.run_context.pc.* = res;
            },
            // ************************************************************
            // *                PC UPDATE JUMP REL                        *
            // ************************************************************
            instructions.PcUpdate.JumpRel => {
                // Check that the res is not null.
                if (operands.res == null) {
                    return error.ResUnconstrainedUsedWithPcUpdateJumpRel;
                }
                // Check that the res is a felt.
                const res = operands.res.?.tryIntoFelt() catch {
                    return error.PcUpdateJumpRelResNotFelt;
                };
                // Update the PC.
                try self.run_context.pc.*.addFeltInPlace(res);
            },
            // ************************************************************
            // *                PC UPDATE JNZ                            *
            // ************************************************************
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
        self: *CairoVM,
        instruction: *const instructions.Instruction,
        operands: OperandsResult,
    ) !void {
        switch (instruction.ap_update) {
            // *********************************************************
            // *                      AP UPDATE ADD                    *
            // *********************************************************
            instructions.ApUpdate.Add => {
                // Check that Res is not null.
                if (operands.res == null) {
                    return error.ApUpdateAddResUnconstrained;
                }
                // Update AP.
                try self.run_context.ap.*.addMaybeRelocatableInplace(operands.res.?);
            },
            // *********************************************************
            // *                    AP UPDATE ADD1                     *
            // *********************************************************
            instructions.ApUpdate.Add1 => {
                self.run_context.ap.*.addUintInPlace(1);
            },
            // *********************************************************
            // *                    AP UPDATE ADD2                     *
            // *********************************************************
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
        self: *CairoVM,
        instruction: *const instructions.Instruction,
        operands: OperandsResult,
    ) !void {
        switch (instruction.fp_update) {
            // *********************************************************
            // *                FP UPDATE AP PLUS 2                    *
            // *********************************************************
            instructions.FpUpdate.APPlus2 => {
                // Update the FP.
                // FP = AP + 2.
                self.run_context.fp.*.offset = self.run_context.ap.*.offset + 2;
            },
            // *********************************************************
            // *                    FP UPDATE DST                      *
            // *********************************************************
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
    pub fn isRunFinished(self: *const CairoVM) bool {
        return self.is_run_finished;
    }

    /// Returns the current ap.
    /// # Returns
    /// - `MaybeRelocatable`: The current ap.
    pub fn getAp(self: *const CairoVM) relocatable.Relocatable {
        return self.run_context.ap.*;
    }

    /// Returns the current fp.
    /// # Returns
    /// - `MaybeRelocatable`: The current fp.
    pub fn getFp(self: *const CairoVM) relocatable.Relocatable {
        return self.run_context.fp.*;
    }

    /// Returns the current pc.
    /// # Returns
    /// - `MaybeRelocatable`: The current pc.
    pub fn getPc(self: *const CairoVM) relocatable.Relocatable {
        return self.run_context.pc.*;
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
) CairoVMError!MaybeRelocatable {
    var res = switch (instruction.res_logic) {
        instructions.ResLogic.Op1 => op_1,
        instructions.ResLogic.Add => {
            var sum = try addOperands(op_0, op_1);
            return sum;
        },
        instructions.ResLogic.Mul => {
            var product = try mulOperands(op_0, op_1);
            return product;
        },
        instructions.ResLogic.Unconstrained => null,
    };
    return res.?;
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
        var felt = try felt_op.tryIntoFelt();

        // Add the felt to the relocatable's offset
        try reloc.addFeltInPlace(felt);

        return relocatable.newFromRelocatable(reloc);
    }

    // Both operands are felts
    const op_0_felt = try op_0.tryIntoFelt();
    const op_1_felt = try op_1.tryIntoFelt();

    // Add the felts and return as a new felt wrapped in a relocatable
    return relocatable.fromFelt(op_0_felt.add(op_1_felt));
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

    const op_0_felt = try op_0.tryIntoFelt();
    const op_1_felt = try op_1.tryIntoFelt();

    // Multiply the felts and return as a new felt wrapped in a relocatable
    return relocatable.fromFelt(op_0_felt.mul(op_1_felt));
}

// *****************************************************************************
// *                       CUSTOM TYPES                                        *
// *****************************************************************************

/// Represents the operands for an instruction.
const OperandsResult = struct {
    dst: MaybeRelocatable,
    res: ?MaybeRelocatable,
    op_0: MaybeRelocatable,
    op_1: MaybeRelocatable,
    dst_addr: relocatable.Relocatable,
    op_0_addr: relocatable.Relocatable,
    op_1_addr: relocatable.Relocatable,

    /// Returns a default instance of the OperandsResult struct.
    pub fn default() OperandsResult {
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

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "update pc regular no imm" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Regular;
    instruction.op_1_addr = instructions.Op1Src.AP;
    const operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        pc.offset,
        1,
    );
}

test "update pc regular with imm" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Regular;
    instruction.op_1_addr = instructions.Op1Src.Imm;
    const operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        pc.offset,
        2,
    );
}

test "update pc jump with operands res null" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jump;
    var operands = OperandsResult.default();
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.ResUnconstrainedUsedWithPcUpdateJump, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump with operands res not relocatable" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jump;
    var operands = OperandsResult.default();
    operands.res = relocatable.fromU64(0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.PcUpdateJumpResNotRelocatable, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump with operands res relocatable" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jump;
    var operands = OperandsResult.default();
    operands.res = relocatable.newFromRelocatable(relocatable.Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        pc.offset,
        42,
    );
}

test "update pc jump rel with operands res null" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.JumpRel;
    var operands = OperandsResult.default();
    operands.res = null;
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.ResUnconstrainedUsedWithPcUpdateJumpRel, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump rel with operands res not felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.JumpRel;
    var operands = OperandsResult.default();
    operands.res = relocatable.newFromRelocatable(relocatable.Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.PcUpdateJumpRelResNotFelt, vm.updatePc(
        &instruction,
        operands,
    ));
}

test "update pc jump rel with operands res felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.JumpRel;
    var operands = OperandsResult.default();
    operands.res = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        pc.offset,
        42,
    );
}

test "update pc update jnz with operands dst zero" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(0);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        pc.offset,
        2,
    );
}

test "update pc update jnz with operands dst not zero op1 not felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(1);
    operands.op_1 = relocatable.newFromRelocatable(relocatable.Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(
        error.TypeMismatchNotFelt,
        vm.updatePc(
            &instruction,
            operands,
        ),
    );
}

test "update pc update jnz with operands dst not zero op1 felt" {

    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.pc_update = instructions.PcUpdate.Jnz;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(1);
    operands.op_1 = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updatePc(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const pc = vm.getPc();
    try expectEqual(
        pc.offset,
        42,
    );
}

test "update ap add with operands res unconstrained" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = instructions.ApUpdate.Add;
    var operands = OperandsResult.default();
    operands.res = null; // Simulate unconstrained res
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try expectError(error.ApUpdateAddResUnconstrained, vm.updateAp(
        &instruction,
        operands,
    ));
}

test "update ap add1" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = instructions.ApUpdate.Add1;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateAp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the AP offset was incremented by 1.
    const ap = vm.getAp();
    try expectEqual(
        ap.offset,
        1,
    );
}

test "update ap add2" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.ap_update = instructions.ApUpdate.Add2;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateAp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the AP offset was incremented by 2.
    const ap = vm.getAp();
    try expectEqual(
        ap.offset,
        2,
    );
}

test "update fp appplus2" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = instructions.FpUpdate.APPlus2;
    var operands = OperandsResult.default();
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateFp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the FP offset was incremented by 2.
    const fp = vm.getFp();
    try expectEqual(
        fp.offset,
        2,
    );
}

test "update fp dst relocatable" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = instructions.FpUpdate.Dst;
    var operands = OperandsResult.default();
    operands.dst = relocatable.newFromRelocatable(relocatable.Relocatable.new(
        0,
        42,
    ));
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateFp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the FP offset was incremented by 2.
    const fp = vm.getFp();
    try expectEqual(
        fp.offset,
        42,
    );
}

test "update fp dst felt" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction.default();
    instruction.fp_update = instructions.FpUpdate.Dst;
    var operands = OperandsResult.default();
    operands.dst = relocatable.fromU64(42);
    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    try vm.updateFp(
        &instruction,
        operands,
    );

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the FP offset was incremented by 2.
    const fp = vm.getFp();
    try expectEqual(
        fp.offset,
        42,
    );
}

test "trace is enabled" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var config = Config{ .proof_mode = false, .enable_trace = true };

    var vm = try CairoVM.init(
        allocator,
        config,
    );
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    // Do nothing

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Check that trace was initialized
    if (!vm.trace_context.isEnabled()) {
        return error.TraceShouldHaveBeenEnabled;
    }
}

test "trace is disabled" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    // Do nothing

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Check that trace was initialized
    if (vm.trace_context.isEnabled()) {
        return error.TraceShouldHaveBeenDisabled;
    }
}

test "set get value in vm memory" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    _ = vm.segments.addSegment();
    _ = vm.segments.addSegment();

    const address = relocatable.Relocatable.new(1, 0);
    const value = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(42));

    _ = try vm.segments.memory.set(address, value);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Verify the value is correctly set to 42.
    const actual_value = try vm.segments.memory.get(address);
    const expected_value = value;
    try expectEqual(expected_value, actual_value);
}

test "compute res op1 works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Op1,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = relocatable.Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = value_op1;

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(expected_res, actual_res);
}

test "compute res add felts works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Add,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = relocatable.Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(5));

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(expected_res, actual_res);
}

test "compute res add felt to offset works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Add,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = relocatable.Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.Relocatable.new(1, 1);
    const op0 = relocatable.newFromRelocatable(value_op0);

    const op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, op0, op1);
    const res = relocatable.Relocatable.new(1, 4);
    const expected_res = relocatable.newFromRelocatable(res);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(expected_res, actual_res);
}

test "compute res add fails two relocs" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Add,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = relocatable.Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.Relocatable.new(1, 0);
    const value_op1 = relocatable.Relocatable.new(1, 1);

    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.newFromRelocatable(value_op1);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectError(error.AddRelocToRelocForbidden, computeRes(&instruction, op0, op1));
}

test "compute res mul works" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Mul,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = relocatable.Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));
    const value_op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(3));

    const actual_res = try computeRes(&instruction, value_op0, value_op1);
    const expected_res = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(6));

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectEqual(expected_res, actual_res);
}

test "compute res mul fails two relocs" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Mul,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = relocatable.Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.Relocatable.new(1, 0);
    const value_op1 = relocatable.Relocatable.new(1, 1);

    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.newFromRelocatable(value_op1);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectError(error.MulRelocForbidden, computeRes(&instruction, op0, op1));
}

test "compute res mul fails felt and reloc" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;
    var instruction = Instruction{
        .off_0 = 0,
        .off_1 = 1,
        .off_2 = 2,
        .dst_reg = instructions.Register.AP,
        .op_0_reg = instructions.Register.AP,
        .op_1_addr = instructions.Op1Src.AP,
        .res_logic = instructions.ResLogic.Mul,
        .pc_update = instructions.PcUpdate.Regular,
        .ap_update = instructions.ApUpdate.Regular,
        .fp_update = instructions.FpUpdate.Regular,
        .opcode = instructions.Opcode.NOp,
    };

    // Create a new VM instance.
    var vm = try CairoVM.init(allocator, .{});
    defer vm.deinit();

    vm.run_context.ap.* = relocatable.Relocatable.new(1, 0);
    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const value_op0 = relocatable.Relocatable.new(1, 0);
    const op0 = relocatable.newFromRelocatable(value_op0);
    const op1 = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(2));

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    try expectError(error.MulRelocForbidden, computeRes(&instruction, op0, op1));
}
