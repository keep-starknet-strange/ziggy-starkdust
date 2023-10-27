// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

// Local imports.
const Memory = @import("memory.zig").Memory;
const relocatable = @import("relocatable.zig");
const starknet_felt = @import("../../math/fields/starknet.zig");

// MemorySegmentManager manages the list of memory segments.
// Also holds metadata useful for the relocation process of
// the memory at the end of the VM run.
pub const MemorySegmentManager = struct {

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************
    /// The allocator used to allocate the memory.
    allocator: Allocator,
    // The size of the used segments.
    segment_used_sizes: std.HashMap(
        u32,
        u32,
        std.hash_map.AutoContext(u32),
        std.hash_map.default_max_load_percentage,
    ),
    // The size of the segments.
    segment_sizes: std.HashMap(
        u32,
        u32,
        std.hash_map.AutoContext(u32),
        std.hash_map.default_max_load_percentage,
    ),
    // The memory.
    memory: *Memory,
    // The public memory offsets.
    // TODO: Use correct type for this.
    public_memory_offsets: std.HashMap(
        u32,
        u32,
        std.hash_map.AutoContext(u32),
        std.hash_map.default_max_load_percentage,
    ),

    // ************************************************************
    // *             MEMORY ALLOCATION AND DEALLOCATION           *
    // ************************************************************

    // Creates a new MemorySegmentManager.
    // # Arguments
    // * `allocator` - The allocator to use for the HashMaps.
    // # Returns
    // A new MemorySegmentManager.
    pub fn init(allocator: Allocator) !*MemorySegmentManager {
        // Create the pointer to the MemorySegmentManager.
        var segment_manager = try allocator.create(MemorySegmentManager);
        // Initialize the values of the MemorySegmentManager struct.
        segment_manager.* = MemorySegmentManager{
            .allocator = allocator,
            .segment_used_sizes = std.AutoHashMap(
                u32,
                u32,
            ).init(allocator),
            .segment_sizes = std.AutoHashMap(
                u32,
                u32,
            ).init(allocator),
            // Initialize the memory pointer.
            .memory = try Memory.init(allocator),
            .public_memory_offsets = std.AutoHashMap(u32, u32).init(allocator),
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
        // Deallocate self.
        self.allocator.destroy(self);
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
    var allocator = std.testing.allocator;

    // Initialize a memory segment manager.
    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    //Allocate a memory segment.
    const relocatable_address_1 = memory_segment_manager.addSegment();

    // Check that the memory segment manager has one segment.
    try expect(memory_segment_manager.memory.num_segments == 1);

    // Check if the relocatable address is correct.
    try expect(relocatable_address_1.segment_index == 0);
    try expect(relocatable_address_1.offset == 0);

    // Allocate another memory segment.
    const relocatable_address_2 = memory_segment_manager.addSegment();

    // Check that the memory segment manager has two segments.
    try expect(memory_segment_manager.memory.num_segments == 2);

    // Check if the relocatable address is correct.
    try expect(relocatable_address_2.segment_index == 1);
    try expect(relocatable_address_2.offset == 0);
}

test "set get integer value in segment memory" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Initialize a memory segment manager.
    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    _ = memory_segment_manager.addSegment();
    _ = memory_segment_manager.addSegment();

    const address = relocatable.Relocatable.new(0, 0);
    const value = relocatable.fromFelt(starknet_felt.Felt252.fromInteger(42));

    const wrong_address = relocatable.Relocatable.new(0, 1);

    _ = try memory_segment_manager.memory.set(address, value);

    try expect(memory_segment_manager.memory.data.contains(address));
    try expect(!memory_segment_manager.memory.data.contains(wrong_address));

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const actual_value = try memory_segment_manager.memory.get(address);
    const expected_value = value;

    try expect(expected_value.eq(actual_value));
}
