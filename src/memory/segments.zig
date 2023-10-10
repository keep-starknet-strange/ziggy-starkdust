// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Local imports.
const Memory = @import("./memory.zig").Memory;

// MemorySegmentManager manages the list of memory segments.
// Also holds metadata useful for the relocation process of
// the memory at the end of the VM run.
pub const MemorySegmentManager = struct {
    segment_used_sizes: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    segment_sizes: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    memory: Memory,
    public_memory_offsets: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),

    pub fn init(allocator: Allocator) MemorySegmentManager {
        return MemorySegmentManager{
            .segment_used_sizes = std.AutoHashMap(u32, u32).init(allocator),
            .segment_sizes = std.AutoHashMap(u32, u32).init(allocator),
            .memory = undefined, // Initialize this appropriately
            .public_memory_offsets = std.AutoHashMap(u32, u32).init(allocator),
        };
    }

    // Adds a memory segment and returns the first address of the new segment
    pub fn addSegment(_: *MemorySegmentManager) void {}
};

test "memory segment manager" {}
