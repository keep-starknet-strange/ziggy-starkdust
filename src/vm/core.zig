// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;

// Local imports.
const segments = @import("memory/segments.zig");
const RunContext = @import("run_context.zig").RunContext;

// Represents the Cairo VM.
pub const CairoVM = struct {
    allocator: *Allocator,
    // The run context.
    run_context: *RunContext,
    // The memory segment manager.
    segments: *segments.MemorySegmentManager,
    // Whether the run is finished or not.
    is_run_finished: bool,

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

    // Do a single step of the VM.
    pub fn step(self: *CairoVM) !void {
        // TODO: implement it.
        // For now we just increase PC and finish the run immediately.
        self.run_context.pc.offset += 1;
        self.is_run_finished = true;
    }

    // Safe deallocation of the VM resources.
    pub fn deinit(self: *CairoVM) void {
        // Deallocate the memory segment manager.
        self.segments.deinit();
        // Deallocate the run context.
        self.run_context.deinit();
    }
};
