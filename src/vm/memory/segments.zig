// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Local imports.
const Memory = @import("memory.zig").Memory;
const relocatable = @import("relocatable.zig");

// MemorySegmentManager manages the list of memory segments.
// Also holds metadata useful for the relocation process of
// the memory at the end of the VM run.
pub const MemorySegmentManager = struct {
    // The size of the used segments.
    segment_used_sizes: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    // The size of the segments.
    segment_sizes: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    // The memory.
    memory: *Memory,
    // The public memory offsets.
    // TODO: Use correct type for this.
    public_memory_offsets: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),

    // Creates a new MemorySegmentManager.
    // # Arguments
    // * `allocator` - The allocator to use for the HashMaps.
    // # Returns
    // A new MemorySegmentManager.
    pub fn init(allocator: Allocator) !MemorySegmentManager {
        // Initialize the memory.
        const memory = allocator.create(Memory) catch unreachable;
        memory.* = try Memory.init(allocator);
        // Cast the memory to a mutable pointer so we can mutate it.
        const mutable_memory = @as(*Memory, memory);
        return MemorySegmentManager{
            .segment_used_sizes = std.AutoHashMap(u32, u32).init(allocator),
            .segment_sizes = std.AutoHashMap(u32, u32).init(allocator),
            .memory = mutable_memory,
            .public_memory_offsets = std.AutoHashMap(u32, u32).init(allocator),
        };
    }

    // Adds a memory segment and returns the first address of the new segment.
    pub fn addSegment(self: *MemorySegmentManager) relocatable.Relocatable {
        // Create the relocatable address for the new segment.
        const relocatable_address = relocatable.Relocatable{
            .segment_index = self.memory.num_segments,
            .offset = 0,
        };

        // Increment the number of segments.
        self.memory.num_segments += 1;

        return relocatable_address;
    }
};

test "memory segment manager" {
    // Initialize an allocator.
    // TODO: Consider using a testing allocator.
    const allocator = std.heap.page_allocator;

    // Initialize a memory segment manager.
    var memory_segment_manager = try MemorySegmentManager.init(allocator);

    // Allocate a memory segment.
    const relocatable_address_1 = memory_segment_manager.addSegment();

    // Check that the memory segment manager has one segment.
    try std.testing.expect(memory_segment_manager.memory.num_segments == 1);

    // Check if the relocatable address is correct.
    try std.testing.expect(relocatable_address_1.segment_index == 0);
    try std.testing.expect(relocatable_address_1.offset == 0);

    // Allocate another memory segment.
    const relocatable_address_2 = memory_segment_manager.addSegment();

    // Check that the memory segment manager has two segments.
    try std.testing.expect(memory_segment_manager.memory.num_segments == 2);

    // Check if the relocatable address is correct.
    try std.testing.expect(relocatable_address_2.segment_index == 1);
    try std.testing.expect(relocatable_address_2.offset == 0);
}
