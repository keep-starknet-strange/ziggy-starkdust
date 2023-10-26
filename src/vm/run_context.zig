// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Local imports.
const Relocatable = @import("memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("memory/relocatable.zig").MaybeRelocatable;

const Instruction = @import("instructions.zig").Instruction;

/// Contains the register states of the Cairo VM.
pub const RunContext = struct {
    /// The allocator used to allocate the memory for the run context.
    allocator: *const Allocator,
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
    pub fn init(allocator: *const Allocator) !*RunContext {
        var run_context = try allocator.create(RunContext);
        run_context.* = RunContext{
            .allocator = allocator,
            .pc = try allocator.create(Relocatable),
            .ap = try allocator.create(Relocatable),
            .fp = try allocator.create(Relocatable),
        };
        run_context.pc.* = Relocatable.default();
        run_context.ap.* = Relocatable.default();
        run_context.fp.* = Relocatable.default();
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
    pub fn init_with_values(
        allocator: *Allocator,
        pc: Relocatable,
        ap: Relocatable,
        fp: Relocatable,
    ) !*RunContext {
        var run_context = try RunContext.init(allocator);
        run_context.pc.* = pc;
        run_context.ap.* = ap;
        run_context.fp.* = fp;
        return run_context;
    }

    /// Safe deallocation of the memory.
    pub fn deinit(self: *RunContext) void {
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
    pub fn compute_dst_addr(
        self: *RunContext,
        instruction: *const Instruction,
    ) !Relocatable {
        var base_addr = switch (instruction.dst_reg) {
            .AP => self.ap.*,
            .FP => self.fp.*,
        };

        if (instruction.off_0 < 0) {
            // Convert i16 to u64 safely and then negate
            const abs_offset = @as(
                u64,
                @intCast(-instruction.off_0),
            );
            return try base_addr.subUint(abs_offset);
        } else {
            // Convert i16 to u64 safely
            const offset = @as(
                u64,
                @intCast(instruction.off_2),
            );
            return try base_addr.addUint(offset);
        }
    }

    /// Compute OP 0 address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the OP 0 address for.
    /// # Returns
    /// - The computed OP 0 address.
    pub fn compute_op_0_addr(
        self: *RunContext,
        instruction: *const Instruction,
    ) !Relocatable {
        var base_addr = switch (instruction.op_0_reg) {
            .AP => self.ap.*,
            .FP => self.fp.*,
        };

        if (instruction.off_1 < 0) {
            // Convert i16 to u64 safely and then negate
            const abs_offset = @as(
                u64,
                @intCast(-instruction.off_1),
            );
            return try base_addr.subUint(abs_offset);
        } else {
            // Convert i16 to u64 safely
            const offset = @as(
                u64,
                @intCast(instruction.off_1),
            );
            return try base_addr.addUint(offset);
        }
    }

    /// Compute OP 1 address for a given instruction.
    /// # Arguments
    /// - instruction: The instruction to compute the OP 1 address for.
    /// # Returns
    /// - The computed OP 1 address.
    pub fn compute_op_1_addr(
        self: *RunContext,
        instruction: *const Instruction,
        op_0: ?MaybeRelocatable,
    ) !Relocatable {
        var base_addr: Relocatable = undefined;
        switch (instruction.op_1_addr) {
            .FP => base_addr = self.fp.*,
            .AP => base_addr = self.ap.*,
            .Imm => {
                if (instruction.off_2 == 1) {
                    base_addr = self.pc.*;
                } else {
                    return error.ImmShouldBe1;
                }
            },
            .Op0 => {
                if (op_0) |val| {
                    base_addr = try val.tryIntoRelocatable();
                } else {
                    return error.UnknownOp0;
                }
            },
        }

        if (instruction.off_2 < 0) {
            // Convert i16 to u64 safely and then negate
            const abs_offset = @as(
                u64,
                @intCast(-instruction.off_2),
            );
            return try base_addr.subUint(abs_offset);
        } else {
            // Convert i16 to u64 safely
            const offset = @as(
                u64,
                @intCast(instruction.off_2),
            );
            return try base_addr.addUint(offset);
        }
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "compute_op1_addr for fp op1 addr" {
    var allocator = std.testing.allocator;

    const instruction =
        Instruction{
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
    };

    const run_context = try RunContext.init_with_values(
        &allocator,
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
    const relocatable_addr = try run_context.compute_op_1_addr(
        &instruction,
        null,
    );

    try expect(relocatable_addr.eq(Relocatable.new(
        0,
        9,
    )));
}
