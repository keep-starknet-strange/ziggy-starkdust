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

    /// The allocator used to allocate the memory for the run context.
    allocator: Allocator,
    /// Program counter (pc) contains the address in memory of the current Cairo
    /// instruction to be executed.
    pc: *Relocatable,
    /// Allocation pointer (ap) , by convention, points to the first memory cell
    /// that has not been used by the program so far. Many instructions may
    /// increase its value by one to indicate that another memory cell has
    /// been used by the instruction. Note that this is merely a convention –
    /// the Cairo machine does not force that the memory cell ap has not been
    /// used, and the programmer may decide to use it in different ways.
    ap: *Relocatable,
    /// Frame pointer (fp) points to the beginning of the stack frame of the current function. The value of fp allows a stack-like behavior: When a
    /// function starts, fp is set to be the same as the current ap, and when
    /// the function returns, fp resumes its previous value. Thus, the value
    /// of fp stays the same for all the instructions in the same invocation
    /// of a function. Due to this property, fp may be used to address the
    // function’s arguments and local variables. See more in Section 6.
    fp: *Relocatable,

    /// Initialize the run context with default values.
    /// # Arguments
    /// - allocator: The allocator to use for allocating the memory for the run context.
    /// # Returns
    /// - The initialized run context.
    /// # Errors
    /// - If a memory allocation fails.
    pub fn init(allocator: Allocator) !*Self {
        const run_context = try allocator.create(Self);
        errdefer allocator.destroy(run_context);

        const pc = try allocator.create(Relocatable);
        errdefer allocator.destroy(pc);
        const ap = try allocator.create(Relocatable);
        errdefer allocator.destroy(ap);
        const fp = try allocator.create(Relocatable);
        errdefer allocator.destroy(fp);

        run_context.* = .{
            .allocator = allocator,
            .pc = pc,
            .ap = ap,
            .fp = fp,
        };
        run_context.pc.* = .{};
        run_context.ap.* = .{};
        run_context.fp.* = .{};

        return run_context;
    }

    /// Initialize the run context with the given values.
    /// # Arguments
    /// - allocator: The allocator to use for allocating the memory for the run context.
    /// - pc: The initial value for the program counter.
    /// - ap: The initial value for the allocation pointer.
    /// - fp: The initial value for the frame pointer.
    /// # Returns
    /// - The initialized run context.
    /// # Errors
    /// - If a memory allocation fails.
    pub fn initWithValues(
        allocator: Allocator,
        pc: Relocatable,
        ap: Relocatable,
        fp: Relocatable,
    ) !*Self {
        const run_context = try Self.init(allocator);
        run_context.pc.* = pc;
        run_context.ap.* = ap;
        run_context.fp.* = fp;
        return run_context;
    }

    /// Safe deallocation of the memory.
    pub fn deinit(self: *Self) void {
        // Deallocate fields.
        self.allocator.destroy(self.pc);
        self.allocator.destroy(self.ap);
        self.allocator.destroy(self.fp);
        // Deallocate self.
        self.allocator.destroy(self);
    }

    /// Compute dst address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the dst address for.
    /// # Returns
    /// - The computed dst address.
    pub fn computeDstAddr(
        self: *Self,
        instruction: *const Instruction,
    ) !Relocatable {
        var base_addr = switch (instruction.dst_reg) {
            .AP => self.ap.*,
            .FP => self.fp.*,
        };

        if (instruction.off_0 < 0) {
            // Convert i16 to u64 safely and then negate
            return try base_addr.subUint(@intCast(-instruction.off_0));
        } else {
            // Convert i16 to u64 safely
            return try base_addr.addUint(@intCast(instruction.off_0));
        }
    }

    /// Compute OP 0 address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the OP 0 address for.
    /// # Returns
    /// - The computed OP 0 address.
    pub fn computeOp0Addr(
        self: *Self,
        instruction: *const Instruction,
    ) !Relocatable {
        var base_addr = switch (instruction.op_0_reg) {
            .AP => self.ap.*,
            .FP => self.fp.*,
        };

        if (instruction.off_1 < 0) {
            // Convert i16 to u64 safely and then negate
            return try base_addr.subUint(@intCast(-instruction.off_1));
        } else {
            // Convert i16 to u64 safely
            return try base_addr.addUint(@intCast(instruction.off_1));
        }
    }

    /// Compute OP 1 address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the OP 1 address for.
    /// # Returns
    /// - The computed OP 1 address.
    pub fn computeOp1Addr(
        self: *Self,
        instruction: *const Instruction,
        op_0: ?MaybeRelocatable,
    ) !Relocatable {
        const base_addr = switch (instruction.op_1_addr) {
            .FP => self.fp.*,
            .AP => self.ap.*,
            .Imm => if (instruction.off_2 == 1) self.pc.* else return error.ImmShouldBe1,
            .Op0 => if (op_0) |val| try val.tryIntoRelocatable() else return error.UnknownOp0,
        };

        if (instruction.off_2 < 0) {
            // Convert i16 to u64 safely and then negate
            return try base_addr.subUint(@intCast(-instruction.off_2));
        } else {
            // Convert i16 to u64 safely
            return try base_addr.addUint(@intCast(instruction.off_2));
        }
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "RunContext: computeDstAddr should return self.ap - instruction.off_0 if instruction.off_0 is negative" {
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            15,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            35,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            40,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            30,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            30,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            40,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            23,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            27,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            40,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            38,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            25,
        ),
        Relocatable.new(
            0,
            30,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            32,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            3,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            9,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            2,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
            0,
            8,
        ),
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
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
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
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
            .{ .relocatable = Relocatable.new(
                0,
                32,
            ) },
        ),
    );
}

test "RunContext: compute_op1_addr for OP0 op1 addr and instruction off_2 > 0" {
    const run_context = try RunContext.initWithValues(
        std.testing.allocator,
        Relocatable.new(
            0,
            4,
        ),
        Relocatable.new(
            0,
            5,
        ),
        Relocatable.new(
            0,
            6,
        ),
    );
    defer run_context.deinit();
    try expectEqual(
        Relocatable.new(
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
            .{ .relocatable = Relocatable.new(
                0,
                32,
            ) },
        ),
    );
}
