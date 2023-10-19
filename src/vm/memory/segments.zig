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

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************

    // The size of the used segments.
    segment_used_sizes: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    // The size of the segments.
    segment_sizes: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    // The memory.
    memory: *Memory,
    // The public memory offsets.
    // TODO: Use correct type for this.
    public_memory_offsets: std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),

    // ************************************************************
    // *             MEMORY ALLOCATION AND DEALLOCATION           *
    // ************************************************************

    // Creates a new MemorySegmentManager.
    // # Arguments
    // * `allocator` - The allocator to use for the HashMaps.
    // # Returns
    // A new MemorySegmentManager.
    pub fn init(allocator: *const Allocator) !*MemorySegmentManager {
        // Create the pointer to the MemorySegmentManager.
        var segment_manager = try allocator.create(MemorySegmentManager);
        // Initialize the values of the MemorySegmentManager struct.
        segment_manager.* = MemorySegmentManager{
            .segment_used_sizes = std.AutoHashMap(u32, u32).init(allocator.*),
            .segment_sizes = std.AutoHashMap(u32, u32).init(allocator.*),
            // Initialize the memory pointer.
            .memory = try Memory.init(allocator),
            .public_memory_offsets = std.AutoHashMap(u32, u32).init(allocator.*),
        };
        // Return the pointer to the MemorySegmentManager.
        return segment_manager;
    }

    // Safe deallocation of the memory.
    pub fn deinit(self: *MemorySegmentManager) void {
        // Clear the hash maps
        self.segment_used_sizes.deinit();
        self.segment_sizes.deinit();
        self.public_memory_offsets.deinit();
        // Deallocate the memory.
        self.memory.deinit();
    }

    // ************************************************************
    // *                        METHODS                           *
    // ************************************************************

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

// ************************************************************
// *                         TESTS                            *
// ************************************************************

test "memory segment manager" {
    // Initialize an allocator.
    // TODO: Consider using a testing allocator.
    var allocator = std.heap.page_allocator;

    // Initialize a memory segment manager.
    var memory_segment_manager = try MemorySegmentManager.init(&allocator);

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
