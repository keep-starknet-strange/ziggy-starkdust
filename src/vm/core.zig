// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;

// Local imports.
const segments = @import("memory/segments.zig");
const RunContext = @import("run_context.zig").RunContext;
const CairoVMError = @import("error.zig").CairoVMError;

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
    pub fn step(self: *CairoVM) error{ InstructionFetchingFailed, InstructionEncodingError }!void {
        // TODO: Run hints.

        // ************************************************************
        // *                    FETCH                                 *
        // ************************************************************

        // During the fetch stage, the instruction is fetched from the memory.
        const encoded_instruction = self.segments.memory.get(self.run_context.pc.*) catch {
            return CairoVMError.InstructionFetchingFailed;
        };

        // ************************************************************
        // *                    DECODE                                *
        // ************************************************************

        // During the decode stage, the instruction is decoded.
        const encoded_instruction_felt = encoded_instruction.intoFelt() catch {
            return CairoVMError.InstructionEncodingError;
        };

        // Print the instruction.
        std.debug.print("Instruction: {}\n", .{encoded_instruction_felt.toInteger()});

        // ************************************************************
        // *                    EXECUTE                               *
        // ************************************************************
    }
};
