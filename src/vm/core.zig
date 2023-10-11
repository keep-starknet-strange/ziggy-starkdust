// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;

// Local imports.
const segments = @import("memory/segments.zig");
const RunContext = @import("run_context.zig").RunContext;

// Represents the Cairo VM.
pub const CairoVM = struct {
    // The run context.
    run_context: *RunContext,
    // The memory segment manager.
    segments: *segments.MemorySegmentManager,
    // Whether the run is finished or not.
    is_run_finished: bool,

    // Creates a new Cairo VM.
    pub fn init(allocator: Allocator) !CairoVM {
        // Initialize the memory segment manager.
        const memory_segment_manager = allocator.create(segments.MemorySegmentManager) catch unreachable;
        memory_segment_manager.* = try segments.MemorySegmentManager.init(allocator);
        // Cast the memory to a mutable pointer so we can mutate it.
        const mutable_memory_segment_manager = @as(*segments.MemorySegmentManager, memory_segment_manager);

        // Initialize the run context.
        var run_context = try RunContext.new(allocator);
        // Cast the run context to a mutable pointer so we can mutate it.
        const mutable_run_context = @as(*RunContext, &run_context);

        return CairoVM{
            .run_context = mutable_run_context,
            .segments = mutable_memory_segment_manager,
            .is_run_finished = false,
        };
    }

    // Do a single step of the VM.
    pub fn step(_: *CairoVM) !void {}
};
