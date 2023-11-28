// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectError = std.testing.expectError;

// Local imports.
const Memory = @import("memory.zig").Memory;
const memoryFile = @import("memory.zig");
const MemoryCell = @import("memory.zig").MemoryCell;
const relocatable = @import("relocatable.zig");
const Relocatable = @import("relocatable.zig").Relocatable;
const MaybeRelocatable = @import("relocatable.zig").MaybeRelocatable;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const MemoryError = @import("../error.zig").MemoryError;

// MemorySegmentManager manages the list of memory segments.
// Also holds metadata useful for the relocation process of
// the memory at the end of the VM run.
pub const MemorySegmentManager = struct {
    const Self = @This();

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************
    /// The allocator used to allocate the memory.
    allocator: Allocator,
    // The size of the used segments.
    segment_used_sizes: std.ArrayHashMap(
        i64,
        u32,
        std.array_hash_map.AutoContext(i64),
        false,
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
    pub fn init(allocator: Allocator) !*Self {
        // Create the pointer to the MemorySegmentManager.
        const segment_manager = try allocator.create(Self);
        errdefer allocator.destroy(segment_manager);

        const memory = try Memory.init(allocator);
        errdefer memory.deinit();

        // Initialize the values of the MemorySegmentManager struct.
        segment_manager.* = .{
            .allocator = allocator,
            .segment_used_sizes = std.AutoArrayHashMap(
                i64,
                u32,
            ).init(allocator),
            .segment_sizes = std.AutoHashMap(
                u32,
                u32,
            ).init(allocator),
            // Initialize the memory pointer.
            .memory = memory,
            .public_memory_offsets = std.AutoHashMap(u32, u32).init(allocator),
        };
        // Return the pointer to the MemorySegmentManager.
        return segment_manager;
    }

    // Safe deallocation of the memory.
    pub fn deinit(self: *Self) void {
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
    pub fn addSegment(self: *Self) !Relocatable {
        // Create the relocatable address for the new segment.
        const relocatable_address = Relocatable{
            .segment_index = self.memory.num_segments,
            .offset = 0,
        };

        // Increment the number of segments.
        self.memory.num_segments += 1;
        try self.memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});

        return relocatable_address;
    }

    // Adds a temporary memory segment and returns the first address of the new segment.
    pub fn addTempSegment(self: *Self) !Relocatable {
        // Increment the number of temporary segments.
        self.memory.num_temp_segments += 1;

        // Create the relocatable address for the new segment.
        const relocatable_address = Relocatable{
            .segment_index = -@as(i64, @intCast(self.memory.num_temp_segments)),
            .offset = 0,
        };
        try self.memory.temp_data.append(std.ArrayListUnmanaged(?MemoryCell){});

        return relocatable_address;
    }

    /// Retrieves the size of a memory segment by its index if available, else returns null.
    ///
    /// # Parameters
    /// - `index` (u32): The index of the memory segment.
    ///
    /// # Returns
    /// A `u32` representing the size of the segment or null if not computed.
    pub fn getSegmentUsedSize(self: *Self, index: u32) ?u32 {
        return self.segment_used_sizes.get(index) orelse null;
    }

    /// Retrieves the number of memory segments.
    ///
    /// # Returns
    ///
    /// The number of memory segments as a `usize`.
    pub fn numSegments(self: *Self) usize {
        return self.memory.data.items.len;
    }

    /// Retrieves the number of temporary memory segments.
    ///
    /// # Returns
    ///
    /// The number of temporary memory segments as a `usize`.
    pub fn numTempSegments(self: *Self) usize {
        return self.memory.temp_data.items.len;
    }

    /// Computes and returns the effective size of memory segments.
    ///
    /// This function iterates through memory segments, calculates their effective sizes, and
    /// updates the segment sizes map accordingly.
    ///
    /// # Returns
    ///
    /// An `AutoArrayHashMap` representing the computed effective sizes of memory segments.
    pub fn computeEffectiveSize(self: *Self, allow_tmp_segments: bool) !std.AutoArrayHashMap(i64, u32) {
        if (self.segment_used_sizes.count() != 0) {
            return self.segment_used_sizes;
        }

        // TODO: Check if memory is frozen. At the time of writting this function memory cannot be frozen so we cannot check if it frozen.

        for (self.memory.data.items, 0..) |segment, i| {
            try self.segment_used_sizes.put(
                @intCast(i),
                @intCast(segment.items.len),
            );
        }

        if (allow_tmp_segments) {
            for (self.memory.temp_data.items, 0..) |segment, i| {
                const key: i64 = @intCast(i);

                try self.segment_used_sizes.put(
                    -(key + 1),
                    @intCast(segment.items.len),
                );
            }
        }
        return self.segment_used_sizes;
    }

    /// Retrieves the size of a memory segment by its index if available, else computes it.
    ///
    /// This function attempts to retrieve the size of a memory segment by its index. If the size
    /// is not available in the segment sizes map, it calculates the effective size and returns it.
    ///
    /// # Parameters
    ///
    /// - `index` (u32): The index of the memory segment.
    ///
    /// # Returns
    ///
    /// A `u32` representing the size of the segment or a computed effective size if not available.
    pub fn getSegmentSize(self: *Self, index: u32) ?u32 {
        return self.segment_sizes.get(index) orelse self.getSegmentUsedSize(index);
    }

    /// Checks if a memory value is valid within the MemorySegmentManager.
    ///
    /// This function validates whether a given memory value is within the bounds
    /// of the memory segments managed by the MemorySegmentManager.
    ///
    /// # Parameters
    ///
    /// - `value` (*MaybeRelocatable): The memory value to validate.
    ///
    /// # Returns
    ///
    /// A boolean value indicating the validity of the memory value.
    pub fn isValidMemoryValue(self: *Self, value: *MaybeRelocatable) bool {
        return switch (value.*) {
            .felt => true,
            .relocatable => |item| @as(
                usize,
                @intCast(item.segment_index),
            ) < self.segment_used_sizes.count(),
        };
    }

    // loadData loads data into the memory managed by MemorySegmentManager.
    //
    // This function iterates through the provided data in reverse order,
    // writing it into memory starting from the given `ptr` address.
    // It uses the allocator to set memory values and handles potential MemoryError.Math exceptions.
    //
    // # Parameters
    // - `allocator` (Allocator): The allocator for memory operations.
    // - `ptr` (Relocatable): The starting address in memory to write the data.
    // - `data` (*std.ArrayList(MaybeRelocatable)): The data to be loaded into memory.
    //
    // # Returns
    // A `Relocatable` representing the first address after the loaded data in memory.
    //
    // # Errors
    // - Returns a MemoryError.Math if there's an issue with memory arithmetic during loading.
    pub fn loadData(
        self: *Self,
        allocator: Allocator,
        ptr: Relocatable,
        data: *std.ArrayList(MaybeRelocatable),
    ) !Relocatable {
        var idx = data.items.len;
        while (idx > 0) : (idx -= 1) {
            const i = idx - 1;
            try self.memory.set(
                allocator,
                try ptr.addUint(@intCast(i)),
                data.items[i],
            );
        }
        return ptr.addUint(data.items.len) catch MemoryError.Math;
    }
};

// Utility function to help set up memory segments
//
// # Arguments
// - `segment_manager` - MemorySegmentManger to be passed in
// - `vals` - complile time structure with heterogenous types
pub fn segmentsUtil(segment_manager: *MemorySegmentManager, allocator: Allocator, comptime vals: anytype) !void {
    try memoryFile.setUpMemory(segment_manager.memory, allocator, vals);
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************

test "memory segment manager" {
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory segment manager.
    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    //Allocate a memory segment.
    const relocatable_address_1 = try memory_segment_manager.addSegment();

    // Check that the memory segment manager has one segment.
    try expect(memory_segment_manager.memory.num_segments == 1);

    //Allocate a temporary memory segment.
    const relocatable_address_2 = try memory_segment_manager.addTempSegment();

    try expect(memory_segment_manager.memory.num_temp_segments == 1);

    // Check if the relocatable address is correct.
    try expectEqual(
        Relocatable{
            .segment_index = 0,
            .offset = 0,
        },
        relocatable_address_1,
    );

    try expectEqual(
        Relocatable{
            .segment_index = -1,
            .offset = 0,
        },
        relocatable_address_2,
    );

    // Allocate another memory segment.
    const relocatable_address_3 = try memory_segment_manager.addSegment();

    // Allocate another temporary memory segment.
    const relocatable_address_4 = try memory_segment_manager.addTempSegment();

    // Check that the memory segment manager has two segments.
    try expect(memory_segment_manager.memory.num_segments == 2);
    // Check that the memory segment manager has two temporary segments.
    try expect(memory_segment_manager.memory.num_temp_segments == 2);

    // Check if the relocatable address is correct.
    try expectEqual(
        Relocatable{
            .segment_index = 1,
            .offset = 0,
        },
        relocatable_address_3,
    );
    try expectEqual(
        Relocatable{
            .segment_index = -2,
            .offset = 0,
        },
        relocatable_address_4,
    );
}

test "set get integer value in segment memory" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory segment manager.
    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************

    const address_1 = Relocatable.new(
        0,
        0,
    );
    const address_2 = Relocatable.new(
        -1,
        0,
    );
    const value_1 = MaybeRelocatable.fromFelt(Felt252.fromInteger(42));

    const value_2 = MaybeRelocatable.fromFelt(Felt252.fromInteger(84));

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{42} },
            .{ .{ -1, 0 }, .{84} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    const actual_value_1 = try memory_segment_manager.memory.get(address_1);
    const expected_value_1 = value_1;
    const actual_value_2 = try memory_segment_manager.memory.get(address_2);
    const expected_value_2 = value_2;

    try expect(expected_value_1.eq(actual_value_1.?));
    try expect(expected_value_2.eq(actual_value_2.?));
}

test "MemorySegmentManager: getSegmentUsedSize should return the size of a memory segment by its index if available" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(10, 4);
    try expectEqual(
        @as(u32, @intCast(4)),
        memory_segment_manager.getSegmentUsedSize(10).?,
    );
}

test "MemorySegmentManager: getSegmentUsedSize should return null if index not available" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectEqual(
        @as(?u32, null),
        memory_segment_manager.getSegmentUsedSize(10),
    );
}

test "MemorySegmentManager: numSegments should return the number of segments in the real memory" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 1 }, .{10} },
            .{ .{ 1, 1 }, .{10} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectEqual(
        @as(usize, 2),
        memory_segment_manager.numSegments(),
    );
}

test "MemorySegmentManager: numSegments should return the number of segments in the temporary memory" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ -1, 1 }, .{10} },
            .{ .{ -2, 1 }, .{10} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectEqual(
        @as(usize, 2),
        memory_segment_manager.numTempSegments(),
    );
}

test "MemorySegmentManager: computeEffectiveSize for one segment memory" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{1} },
            .{ .{ 0, 2 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(false);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 3), actual.get(0).?);
}

test "MemorySegmentManager: computeEffectiveSize for one segment memory with gap" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{.{ .{ 0, 6 }, .{1} }},
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(false);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 7), actual.get(0).?);
}

test "MemorySegmentManager: computeEffectiveSize for one segment memory with gaps" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 3 }, .{1} },
            .{ .{ 0, 4 }, .{1} },
            .{ .{ 0, 7 }, .{1} },
            .{ .{ 0, 9 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(false);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 10), actual.get(0).?);
}

test "MemorySegmentManager: computeEffectiveSize for three segment memory" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{1} },
            .{ .{ 0, 2 }, .{1} },
            .{ .{ 1, 0 }, .{1} },
            .{ .{ 1, 1 }, .{1} },
            .{ .{ 1, 2 }, .{1} },
            .{ .{ 2, 0 }, .{1} },
            .{ .{ 2, 1 }, .{1} },
            .{ .{ 2, 2 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(false);

    try expectEqual(@as(usize, 3), actual.count());
    try expectEqual(@as(u32, 3), actual.get(0).?);
    try expectEqual(@as(u32, 3), actual.get(1).?);
    try expectEqual(@as(u32, 3), actual.get(2).?);
}

test "MemorySegmentManager: computeEffectiveSize for three segment memory with gaps" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 2 }, .{1} },
            .{ .{ 0, 5 }, .{1} },
            .{ .{ 0, 7 }, .{1} },

            .{ .{ 1, 1 }, .{1} },

            .{ .{ 2, 2 }, .{1} },
            .{ .{ 2, 4 }, .{1} },
            .{ .{ 2, 7 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(false);

    try expectEqual(@as(usize, 3), actual.count());
    try expectEqual(@as(u32, 8), actual.get(0).?);
    try expectEqual(@as(u32, 2), actual.get(1).?);
    try expectEqual(@as(u32, 8), actual.get(2).?);
}

test "MemorySegmentManager: computeEffectiveSize (with temp segments) for one segment memory" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ -1, 0 }, .{1} },
            .{ .{ -1, 1 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(true);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 2), actual.get(-1).?);
}

test "MemorySegmentManager: computeEffectiveSize (with temp segments) for one segment memory with gap" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    _ = try memory_segment_manager.addTempSegment();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{.{ .{ -1, 6 }, .{1} }},
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(true);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 7), actual.get(-1).?);
}

test "MemorySegmentManager: computeEffectiveSize (with temp segments) for one segment memory with gaps" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ -1, 3 }, .{1} },
            .{ .{ -1, 4 }, .{1} },
            .{ .{ -1, 7 }, .{1} },
            .{ .{ -1, 9 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(true);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 10), actual.get(-1).?);
}

test "MemorySegmentManager: computeEffectiveSize (with temp segments) for three segment memory" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ -3, 0 }, .{1} },
            .{ .{ -3, 1 }, .{1} },
            .{ .{ -3, 2 }, .{1} },

            .{ .{ -2, 0 }, .{1} },
            .{ .{ -2, 1 }, .{1} },
            .{ .{ -2, 2 }, .{1} },

            .{ .{ -1, 0 }, .{1} },
            .{ .{ -1, 1 }, .{1} },
            .{ .{ -1, 2 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(true);

    try expectEqual(@as(usize, 3), actual.count());
    try expectEqual(@as(u32, 3), actual.get(-1).?);
    try expectEqual(@as(u32, 3), actual.get(-2).?);
    try expectEqual(@as(u32, 3), actual.get(-3).?);
}

test "MemorySegmentManager: computeEffectiveSize (with temp segments) for three segment memory with gaps" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ -3, 2 }, .{1} },
            .{ .{ -3, 5 }, .{1} },
            .{ .{ -3, 7 }, .{1} },

            .{ .{ -2, 1 }, .{1} },

            .{ .{ -1, 2 }, .{1} },
            .{ .{ -1, 4 }, .{1} },
            .{ .{ -1, 7 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(true);

    try expectEqual(@as(usize, 3), actual.count());
    try expectEqual(@as(u32, 8), actual.get(-3).?);
    try expectEqual(@as(u32, 2), actual.get(-2).?);
    try expectEqual(@as(u32, 8), actual.get(-1).?);
}

test "MemorySegmentManager: getSegmentUsedSize after computeEffectiveSize" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memoryFile.setUpMemory(
        memory_segment_manager.memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 2 }, .{1} },
            .{ .{ 0, 5 }, .{1} },
            .{ .{ 0, 7 }, .{1} },

            .{ .{ 1, 1 }, .{1} },

            .{ .{ 2, 2 }, .{1} },
            .{ .{ 2, 4 }, .{1} },
            .{ .{ 2, 7 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    _ = try memory_segment_manager.computeEffectiveSize(false);

    try expectEqual(@as(usize, 3), memory_segment_manager.segment_used_sizes.count());
    try expectEqual(@as(u32, 8), memory_segment_manager.segment_used_sizes.get(0).?);
    try expectEqual(@as(u32, 2), memory_segment_manager.segment_used_sizes.get(1).?);
    try expectEqual(@as(u32, 8), memory_segment_manager.segment_used_sizes.get(2).?);
}

test "MemorySegmentManager: getSegmentSize should return the size of the segment if contained in segment_sizes" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_sizes.put(10, 105);
    try expectEqual(@as(u32, 105), memory_segment_manager.getSegmentSize(10).?);
}

test "MemorySegmentManager: getSegmentSize should return the size of the segment via getSegmentUsedSize if not contained in segment_sizes" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(3, 6);
    try expectEqual(@as(u32, 6), memory_segment_manager.getSegmentSize(3).?);
}

test "MemorySegmentManager: getSegmentSize should return null if missing segment" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectEqual(@as(?u32, null), memory_segment_manager.getSegmentSize(3));
}

test "MemorySegmentManager: isValidMemoryValue should return true if Felt" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    var value: MaybeRelocatable = .{ .felt = Felt252.zero() };
    try expect(memory_segment_manager.isValidMemoryValue(&value));
}

test "MemorySegmentManager: isValidMemoryValue should return false if invalid segment" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(0, 10);
    var value: MaybeRelocatable = .{ .relocatable = Relocatable.new(1, 1) };
    try expect(!memory_segment_manager.isValidMemoryValue(&value));
}

test "MemorySegmentManager: isValidMemoryValue should return true if valid segment" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(0, 10);
    var value: MaybeRelocatable = MaybeRelocatable.fromSegment(0, 5);
    try expect(memory_segment_manager.isValidMemoryValue(&value));
}

test "MemorySegmentManager: getSegmentUsedSize should return null if segments not computed" {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectEqual(
        @as(?u32, null),
        memory_segment_manager.getSegmentUsedSize(5),
    );
}

test "MemorySegmentManager: getSegmentUsedSize should return the size of the used segments." {
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(5, 4);
    try memory_segment_manager.segment_used_sizes.put(0, 22);
    try expectEqual(
        @as(?u32, 22),
        memory_segment_manager.getSegmentUsedSize(0),
    );
    try expectEqual(
        @as(?u32, 4),
        memory_segment_manager.getSegmentUsedSize(5),
    );
}

test "MemorySegmentManager: segments utility function for testing test" {
    const allocator = std.testing.allocator;

    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    try segmentsUtil(
        memory_segment_manager,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{1} },
            .{ .{ 0, 2 }, .{1} },
        },
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    var actual = try memory_segment_manager.computeEffectiveSize(false);

    try expectEqual(@as(usize, 1), actual.count());
    try expectEqual(@as(u32, 3), actual.get(0).?);
}

test "MemorySegmentManager: loadData with empty data" {
    const allocator = std.testing.allocator;

    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    var data = std.ArrayList(MaybeRelocatable).init(allocator);
    defer data.deinit();

    try expectEqual(
        Relocatable.new(0, 3),
        try memory_segment_manager.loadData(
            allocator,
            Relocatable.new(0, 3),
            &data,
        ),
    );
}

test "MemorySegmentManager: loadData with one element" {
    const allocator = std.testing.allocator;

    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    var data = std.ArrayList(MaybeRelocatable).init(allocator);
    defer data.deinit();
    try data.append(MaybeRelocatable.fromU256(4));

    _ = try memory_segment_manager.addSegment();

    const actual = try memory_segment_manager.loadData(
        allocator,
        Relocatable.new(0, 0),
        &data,
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectEqual(Relocatable.new(0, 1), actual);
    try expectEqual(
        MaybeRelocatable.fromU256(4),
        (try memory_segment_manager.memory.get(Relocatable.new(0, 0))).?,
    );
}

test "MemorySegmentManager: loadData with three elements" {
    const allocator = std.testing.allocator;

    var memory_segment_manager = try MemorySegmentManager.init(allocator);
    defer memory_segment_manager.deinit();

    var data = std.ArrayList(MaybeRelocatable).init(allocator);
    defer data.deinit();
    try data.append(MaybeRelocatable.fromU256(4));
    try data.append(MaybeRelocatable.fromU256(5));
    try data.append(MaybeRelocatable.fromU256(6));

    _ = try memory_segment_manager.addSegment();

    const actual = try memory_segment_manager.loadData(
        allocator,
        Relocatable.new(0, 0),
        &data,
    );
    defer memory_segment_manager.memory.deinitData(std.testing.allocator);

    try expectEqual(Relocatable.new(0, 3), actual);
    try expectEqual(
        MaybeRelocatable.fromU256(4),
        (try memory_segment_manager.memory.get(Relocatable.new(0, 0))).?,
    );
    try expectEqual(
        MaybeRelocatable.fromU256(5),
        (try memory_segment_manager.memory.get(Relocatable.new(0, 1))).?,
    );
    try expectEqual(
        MaybeRelocatable.fromU256(6),
        (try memory_segment_manager.memory.get(Relocatable.new(0, 2))).?,
    );
}
