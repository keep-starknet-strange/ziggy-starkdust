// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;

// Local imports.
const segments = @import("memory/segments.zig");
const relocatable = @import("memory/relocatable.zig");
const instructions = @import("instructions.zig");
const RunContext = @import("run_context.zig").RunContext;
const CairoVMError = @import("error.zig").CairoVMError;

/// Represents the Cairo VM.
pub const CairoVM = struct {

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************

    /// The memory allocator. Can be needed for the deallocation of the VM resources.
    allocator: *Allocator,
    /// The run context.
    run_context: *RunContext,
    /// The memory segment manager.
    segments: *segments.MemorySegmentManager,
    /// Whether the run is finished or not.
    is_run_finished: bool,

    // ************************************************************
    // *             MEMORY ALLOCATION AND DEALLOCATION           *
    // ************************************************************

    /// Creates a new Cairo VM.
    /// # Arguments
    /// - `allocator`: The allocator to use for the VM.
    /// # Returns
    /// - `CairoVM`: The created VM.
    /// # Errors
    /// - If a memory allocation fails.
    pub fn init(allocator: *Allocator) !CairoVM {
        // Initialize the memory segment manager.
        const memory_segment_manager = try segments.MemorySegmentManager.init(allocator);
        // Initialize the run context.
        const run_context = try RunContext.init(allocator);

        return CairoVM{
            .allocator = allocator,
            .run_context = run_context,
            .segments = memory_segment_manager,
            .is_run_finished = false,
        };
    }

    /// Safe deallocation of the VM resources.
    pub fn deinit(self: *CairoVM) void {
        // Deallocate the memory segment manager.
        self.segments.deinit();
        // Deallocate the run context.
        self.run_context.deinit();
    }

    // ************************************************************
    // *                        METHODS                           *
    // ************************************************************

    /// Do a single step of the VM.
    /// Process an instruction cycle using the typical fetch-decode-execute cycle.
    pub fn step(self: *CairoVM) !void {
        // TODO: Run hints.

        std.log.debug("Running instruction at pc: {d}", .{self.run_context.pc.*});

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
    pub fn runInstruction(self: *CairoVM, instruction: *const instructions.Instruction) !void {
        const operands_result = try self.computeOperands(instruction);
        _ = operands_result;
    }

    /// Compute the operands for a given instruction.
    /// # Arguments
    /// - `instruction`: The instruction to compute the operands for.
    /// # Returns
    /// - `Operands`: The operands for the instruction.
    pub fn computeOperands(self: *CairoVM, instruction: *const instructions.Instruction) !OperandsResult {
        // Compute the destination address and get value from the memory.
        const dst_addr = try self.run_context.compute_dst_addr(instruction);
        const dst = try self.segments.memory.get(dst_addr);
        _ = dst;

        // Compute the OP 0 address and get value from the memory.
        const op_0_addr = try self.run_context.compute_op_0_addr(instruction);
        // Here we use `catch null` because we want op_0_op to be optional since it's not always used.
        const op_0_op = self.segments.memory.get(op_0_addr) catch null;

        // Compute the OP 1 address and get value from the memory.
        const op_1_addr = try self.run_context.compute_op_1_addr(instruction, op_0_op);
        const op_1_op = try self.segments.memory.get(op_1_addr);
        _ = op_1_op;

        return OperandsResult{
            .dst = relocatable.fromU64(0),
            .res = relocatable.fromU64(0),
            .op_0 = relocatable.fromU64(0),
            .op_1 = relocatable.fromU64(0),
            .dst_addr = relocatable.fromU64(0),
            .op_0_addr = relocatable.fromU64(0),
            .op_1_addr = relocatable.fromU64(0),
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
    pub fn computeOp0Deductions(self: *CairoVM, op_0_addr: relocatable.MaybeRelocatable, instruction: *const instructions.Instruction, dst: ?relocatable.MaybeRelocatable, op1: ?relocatable.MaybeRelocatable) void {
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
    pub fn deduceMemoryCell(self: *CairoVM, address: relocatable.Relocatable) !?relocatable.MaybeRelocatable {
        _ = address;
        _ = self;
        return null;
    }
};

// *****************************************************************************
// *                       CUSTOM TYPES                                        *
// *****************************************************************************

/// Represents the operands for an instruction.
const OperandsResult = struct {
    dst: relocatable.MaybeRelocatable,
    res: relocatable.MaybeRelocatable,
    op_0: relocatable.MaybeRelocatable,
    op_1: relocatable.MaybeRelocatable,
    dst_addr: relocatable.MaybeRelocatable,
    op_0_addr: relocatable.MaybeRelocatable,
    op_1_addr: relocatable.MaybeRelocatable,
};
