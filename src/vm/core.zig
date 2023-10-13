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

// *****************************************************************************
// *                       CUSTOM TYPES                                        *
// *****************************************************************************

const Operands = struct {
    dst: relocatable.MaybeRelocatable,
    res: relocatable.MaybeRelocatable,
    op_0: relocatable.MaybeRelocatable,
    op_1: relocatable.MaybeRelocatable,
};

const OperandsAddresses = struct {
    dst_addr: relocatable.MaybeRelocatable,
    op_0_addr: relocatable.MaybeRelocatable,
    op_1_addr: relocatable.MaybeRelocatable,
};

const OperandsResult = struct {
    operands: Operands,
    addresses: OperandsAddresses,
};

// Represents the Cairo VM.
pub const CairoVM = struct {

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************

    // The memory allocator. Can be needed for the deallocation of the VM resources.
    allocator: *Allocator,
    // The run context.
    run_context: *RunContext,
    // The memory segment manager.
    segments: *segments.MemorySegmentManager,
    // Whether the run is finished or not.
    is_run_finished: bool,

    // ************************************************************
    // *             MEMORY ALLOCATION AND DEALLOCATION           *
    // ************************************************************

    // Creates a new Cairo VM.
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

    // Safe deallocation of the VM resources.
    pub fn deinit(self: *CairoVM) void {
        // Deallocate the memory segment manager.
        self.segments.deinit();
        // Deallocate the run context.
        self.run_context.deinit();
    }

    // ************************************************************
    // *                        METHODS                           *
    // ************************************************************

    // Do a single step of the VM.
    // Process an instruction cycle using the typical fetch-decode-execute cycle.
    pub fn step(self: *CairoVM) !void {
        // TODO: Run hints.

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
        return self.run_instruction(&instruction);
    }

    // Run a specific instruction.
    // # Arguments
    // - `instruction`: The instruction to run.
    pub fn run_instruction(self: *CairoVM, instruction: *const instructions.Instruction) !void {
        const operands_result = try self.compute_operands(instruction);
        const operands = operands_result.operands;
        _ = operands;
        const operands_addresses = operands_result.addresses;
        _ = operands_addresses;
    }

    // Compute the operands for a given instruction.
    // # Arguments
    // - `instruction`: The instruction to compute the operands for.
    // # Returns
    // - `Operands`: The operands for the instruction.
    pub fn compute_operands(self: *CairoVM, instruction: *const instructions.Instruction) !OperandsResult {
        _ = instruction;
        _ = self;

        const operands = Operands{
            .dst = relocatable.fromU64(0),
            .res = relocatable.fromU64(0),
            .op_0 = relocatable.fromU64(0),
            .op_1 = relocatable.fromU64(0),
        };
        const operands_addresses = OperandsAddresses{
            .dst_addr = relocatable.fromU64(0),
            .op_0_addr = relocatable.fromU64(0),
            .op_1_addr = relocatable.fromU64(0),
        };
        return OperandsResult{
            .operands = operands,
            .addresses = operands_addresses,
        };
    }
};
