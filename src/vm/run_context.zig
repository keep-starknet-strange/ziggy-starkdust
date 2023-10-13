// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Local imports.
const Relocatable = @import("memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("memory/relocatable.zig").MaybeRelocatable;

const Instruction = @import("instructions.zig").Instruction;

// Contains the register states of the Cairo VM.
pub const RunContext = struct {
    allocator: *Allocator,
    pc: *Relocatable,
    ap: *Relocatable,
    fp: *Relocatable,

    pub fn init(allocator: *Allocator) !*RunContext {
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

    // Safe deallocation of the memory.
    pub fn deinit(self: *RunContext) void {
        self.allocator.destroy(self.pc);
        self.allocator.destroy(self.ap);
        self.allocator.destroy(self.fp);
    }

    // Compute dst address for a given instruction.
    // # Arguments
    // - instruction: The instruction to compute the dst address for.
    // # Returns
    // - The computed dst address.
    pub fn compute_dst_addr(self: *RunContext, instruction: *const Instruction) !Relocatable {
        var base_addr = switch (instruction.dst_reg) {
            .AP => return self.ap.*,
            .FP => return self.fp.*,
        };

        if (instruction.off_0 < 0) {
            return base_addr.subUint(instruction.off_0);
        } else {
            return base_addr.addUint(instruction.off_0);
        }
    }

    // Compute OP 0 address for a given instruction.
    // # Arguments
    // - instruction: The instruction to compute the OP 0 address for.
    // # Returns
    // - The computed OP 0 address.
    pub fn compute_op_0_addr(self: *RunContext, instruction: *const Instruction) !Relocatable {
        var base_addr = switch (instruction.op_0_reg) {
            .AP => return self.ap.*,
            .FP => return self.fp.*,
        };

        if (instruction.off_1 < 0) {
            return base_addr.subUint(instruction.off_1);
        } else {
            return base_addr.addUint(instruction.off_1);
        }
    }

    // Compute OP 1 address for a given instruction.
    // # Arguments
    // - instruction: The instruction to compute the OP 1 address for.
    // # Returns
    // - The computed OP 1 address.
    pub fn compute_op_1_addr(self: *RunContext, instruction: *const Instruction, op_0: *const MaybeRelocatable) !Relocatable {
        // TODO: Make op_0 optional, since it's not used for all instructions.
        _ = op_0;
        var base_addr = switch (instruction.op_1_addr) {
            .FP => return self.fp.*,
            .AP => return self.ap.*,
            .Imm => if (instruction.off_2 == 1) {
                return self.pc.*;
            } else {
                return error.UnknownOp0;
            },
            // TODO: Implement this.
            .Op0 => return Relocatable.default(),
        };

        if (instruction.off_2 < 0) {
            return base_addr.subUint(instruction.off_2);
        } else {
            return base_addr.addUint(instruction.off_2);
        }
    }
};
