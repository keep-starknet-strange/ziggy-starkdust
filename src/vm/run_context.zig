// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Local imports.
const Relocatable = @import("memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("memory/relocatable.zig").MaybeRelocatable;
const Instruction = @import("instructions.zig").Instruction;

/// Contains the register states of the Cairo VM.
pub const RunContext = struct {
    const Self = @This();

    /// ProgramJson counter (pc) contains the address in memory of the current Cairo
    /// instruction to be executed.
    pc: Relocatable = .{},
    /// Allocation pointer (ap) , by convention, points to the first memory cell
    /// that has not been used by the program so far. Many instructions may
    /// increase its value by one to indicate that another memory cell has
    /// been used by the instruction. Note that this is merely a convention –
    /// the Cairo machine does not force that the memory cell ap has not been
    /// used, and the programmer may decide to use it in different ways.
    ap: u64 = 0,
    /// Frame pointer (fp) points to the beginning of the stack frame of the current function. The value of fp allows a stack-like behavior: When a
    /// function starts, fp is set to be the same as the current ap, and when
    /// the function returns, fp resumes its previous value. Thus, the value
    /// of fp stays the same for all the instructions in the same invocation
    /// of a function. Due to this property, fp may be used to address the
    // function’s arguments and local variables. See more in Section 6.
    fp: u64 = 0,

    /// Initialize the run context with default values.
    /// # Arguments
    /// - pc: The initial value for the program counter.
    /// - ap: The initial value for the allocation pointer.
    /// - fp: The initial value for the frame pointer.
    /// # Returns
    /// - The initialized run context.
    pub fn init(
        pc: Relocatable,
        ap: u64,
        fp: u64,
    ) Self {
        return .{
            .pc = pc,
            .ap = ap,
            .fp = fp,
        };
    }

    /// Compute dst address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the dst address for.
    /// # Returns
    /// - The computed dst address.
    pub fn computeDstAddr(
        self: Self,
        instruction: *const Instruction,
    ) !Relocatable {
        var base_addr = switch (instruction.dst_reg) {
            .AP => self.getAP(),
            .FP => self.getFP(),
        };

        return if (instruction.off_0 < 0)
            // Convert i16 to u64 safely and then negate
            try base_addr.subUint(@abs(instruction.off_0))
        else
            // Convert i16 to u64 safely
            try base_addr.addUint(@intCast(instruction.off_0));
    }

    /// Compute OP 0 address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the OP 0 address for.
    /// # Returns
    /// - The computed OP 0 address.
    pub fn computeOp0Addr(
        self: Self,
        instruction: *const Instruction,
    ) !Relocatable {
        var base_addr = switch (instruction.op_0_reg) {
            .AP => self.getAP(),
            .FP => self.getFP(),
        };

        return if (instruction.off_1 < 0)
            // Convert i16 to u64 safely and then negate
            try base_addr.subUint(@abs(instruction.off_1))
        else
            // Convert i16 to u64 safely
            try base_addr.addUint(@intCast(instruction.off_1));
    }

    /// Compute OP 1 address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the OP 1 address for.
    /// # Returns
    /// - The computed OP 1 address.
    pub fn computeOp1Addr(
        self: Self,
        instruction: *const Instruction,
        op_0: ?MaybeRelocatable,
    ) !Relocatable {
        const base_addr = switch (instruction.op_1_addr) {
            .FP => self.getFP(),
            .AP => self.getAP(),
            .Imm => if (instruction.off_2 == 1) self.pc else return error.ImmShouldBe1,
            .Op0 => if (op_0) |val| try val.intoRelocatable() else return error.UnknownOp0,
        };

        return if (instruction.off_2 < 0)
            // Convert i16 to u64 safely and then negate
            try base_addr.subUint(@abs(instruction.off_2))
        else
            // Convert i16 to u64 safely
            return try base_addr.addUint(@intCast(instruction.off_2));
    }

    /// Returns the current frame pointer (FP) of the run context.
    /// This is the base address for local variables in the current frame.
    ///
    /// # Returns
    /// - The `Relocatable` value of the frame pointer.
    pub fn getFP(self: Self) Relocatable {
        return .{ .segment_index = 1, .offset = self.fp };
    }

    /// Returns the current allocation pointer (AP) of the run context.
    /// This is the pointer used for allocating new memory in the current frame.
    ///
    /// # Returns
    /// - The `Relocatable` value of the allocation pointer.
    pub fn getAP(self: *const Self) Relocatable {
        return .{ .segment_index = 1, .offset = self.ap };
    }

    /// Returns the current program counter (PC) of the run context.
    /// This is the address of the next instruction to be executed.
    ///
    /// # Returns
    /// - The `Relocatable` value of the program counter.
    pub fn getPC(self: *const Self) Relocatable {
        return self.pc;
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "RunContext: computeDstAddr should return self.ap - instruction.off_0 if instruction.off_0 is negative" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 6);

    try expectEqual(
        Relocatable.init(1, 15),
        try run_context.computeDstAddr(&.{
            .off_0 = -10,
            .off_1 = 2,
            .off_2 = 3,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: computeDstAddr should return self.ap + instruction.off_0 if instruction.off_0 is positive" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 6);

    try expectEqual(
        Relocatable.init(1, 35),
        try run_context.computeDstAddr(&.{
            .off_0 = 10,
            .off_1 = 2,
            .off_2 = 3,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: computeDstAddr should return self.fp - instruction.off_0 if instruction.off_0 is negative" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 40);
    try expectEqual(
        Relocatable.init(1, 30),
        try run_context.computeDstAddr(&.{
            .off_0 = -10,
            .off_1 = 2,
            .off_2 = 3,
            .dst_reg = .FP,
            .op_0_reg = .AP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: computeDstAddr should return self.fp + instruction.off_0 if instruction.off_0 is positive" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 30);
    try expectEqual(
        Relocatable.init(1, 40),
        try run_context.computeDstAddr(&.{
            .off_0 = 10,
            .off_1 = 2,
            .off_2 = 3,
            .dst_reg = .FP,
            .op_0_reg = .AP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: computeOp0Addr should return self.ap - instruction.off_1 if instruction.off_1 is negative" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 6);

    try expectEqual(
        Relocatable.init(1, 23),
        try run_context.computeOp0Addr(&.{
            .off_0 = 10,
            .off_1 = -2,
            .off_2 = 3,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: computeOp0Addr should return self.ap + instruction.off_1 if instruction.off_1 is positive" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 6);

    try expectEqual(
        Relocatable.init(1, 27),
        try run_context.computeOp0Addr(&.{
            .off_0 = 10,
            .off_1 = 2,
            .off_2 = 3,
            .dst_reg = .AP,
            .op_0_reg = .AP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: computeOp0Addr should return self.fp - instruction.off_1 if instruction.off_1 is negative" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 40);

    try expectEqual(
        Relocatable.init(1, 38),
        try run_context.computeOp0Addr(&.{
            .off_0 = 10,
            .off_1 = -2,
            .off_2 = 3,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: computeOp0Addr should return self.fp + instruction.off_1 if instruction.off_1 is positive" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 25, 30);

    try expectEqual(
        Relocatable.init(1, 32),
        try run_context.computeOp0Addr(&.{
            .off_0 = 10,
            .off_1 = 2,
            .off_2 = 3,
            .dst_reg = .FP,
            .op_0_reg = .FP,
            .op_1_addr = .FP,
            .res_logic = .Add,
            .pc_update = .Regular,
            .ap_update = .Regular,
            .fp_update = .Regular,
            .opcode = .NOp,
        }),
    );
}

test "RunContext: compute_op1_addr for FP op1 addr and instruction off_2 < 0" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectEqual(
        Relocatable.init(1, 3),
        try run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = -3,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .FP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            null,
        ),
    );
}

test "RunContext: compute_op1_addr for FP op1 addr and instruction off_2 > 0" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectEqual(
        Relocatable.init(1, 9),
        try run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = 3,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .FP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            null,
        ),
    );
}

test "RunContext: compute_op1_addr for AP op1 addr and instruction off_2 < 0" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectEqual(
        Relocatable.init(1, 2),
        try run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = -3,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            null,
        ),
    );
}

test "RunContext: compute_op1_addr for AP op1 addr and instruction off_2 > 0" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectEqual(
        Relocatable.init(1, 8),
        try run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = 3,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .AP,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            null,
        ),
    );
}

test "RunContext: compute_op1_addr for IMM op1 addr and instruction off_2 != 1" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectError(
        error.ImmShouldBe1,
        run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = -3,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            null,
        ),
    );
}

test "RunContext: compute_op1_addr for IMM op1 addr and instruction off_2 == 1" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectEqual(
        Relocatable.init(
            0,
            5,
        ),
        try run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = 1,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .Imm,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            null,
        ),
    );
}

test "RunContext: compute_op1_addr for OP0 op1 addr and instruction op_0 is null" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectError(
        error.UnknownOp0,
        run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = -3,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .Op0,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            null,
        ),
    );
}

test "RunContext: compute_op1_addr for OP0 op1 addr and instruction off_2 < 0" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectEqual(
        Relocatable.init(
            0,
            28,
        ),
        try run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = -4,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .Op0,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            .{ .relocatable = Relocatable.init(
                0,
                32,
            ) },
        ),
    );
}

test "RunContext: compute_op1_addr for OP0 op1 addr and instruction off_2 > 0" {
    const run_context = RunContext.init(Relocatable.init(0, 4), 5, 6);

    try expectEqual(
        Relocatable.init(
            0,
            36,
        ),
        try run_context.computeOp1Addr(
            &.{
                .off_0 = 1,
                .off_1 = 2,
                .off_2 = 4,
                .dst_reg = .FP,
                .op_0_reg = .AP,
                .op_1_addr = .Op0,
                .res_logic = .Add,
                .pc_update = .Regular,
                .ap_update = .Regular,
                .fp_update = .Regular,
                .opcode = .NOp,
            },
            .{ .relocatable = Relocatable.init(
                0,
                32,
            ) },
        ),
    );
}
