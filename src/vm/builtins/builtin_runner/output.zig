const std = @import("std");

const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const Error = @import("../../error.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const MemoryError = Error.MemoryError;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Output built-in runner
pub const OutputBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: usize,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,

    /// Create a new OutputBuiltinRunner instance.
    ///
    /// This function initializes a new `OutputBuiltinRunner` instance with the provided `included` value.
    ///
    /// # Arguments
    ///
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `OutputBuiltinRunner` instance.
    pub fn init(included: bool) Self {
        return .{
            .base = 0,
            .stop_ptr = null,
            .included = included,
        };
    }

    /// Initializes segments for the OutputBuiltinRunner instance using the provided MemorySegmentManager.
    ///
    /// This function sets the base address for the OutputBuiltinRunner instance by adding a segment through the MemorySegmentManager.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// An error if the addition of the segment fails, otherwise sets the base address successfully.
    pub fn initializeSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    /// Generates an initial stack for the OutputBuiltinRunner instance.
    ///
    /// This function initializes an ArrayList of MaybeRelocatable elements representing the initial stack.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `allocator`: The allocator to initialize the ArrayList.
    ///
    /// # Returns
    ///
    /// An ArrayList of MaybeRelocatable elements representing the initial stack.
    /// If the instance is marked as included, a single element initialized with the base address is returned.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        if (self.included) {
            try result.append(MaybeRelocatable.fromSegment(
                @intCast(self.base),
                0,
            ));
            return result;
        }
        return result;
    }

    /// Retrieves the number of used memory cells for the OutputBuiltinRunner instance.
    ///
    /// This function queries the MemorySegmentManager to obtain the count of used cells
    /// based on the base address of the OutputBuiltinRunner.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// The count of used memory cells associated with the OutputBuiltinRunner's base address.
    /// If the information is unavailable, it returns MemoryError.MissingSegmentUsedSizes.
    pub fn getUsedCells(self: *Self, segments: *MemorySegmentManager) !u32 {
        return segments.getSegmentUsedSize(
            @intCast(self.base),
        ) orelse MemoryError.MissingSegmentUsedSizes;
    }

    /// Retrieves the count of used instances for the OutputBuiltinRunner instance.
    ///
    /// This function acts as an alias for `getUsedCells`, obtaining the number of used instances
    /// based on the OutputBuiltinRunner's base address through the MemorySegmentManager.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the OutputBuiltinRunner instance.
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    ///
    /// # Returns
    ///
    /// The count of used instances associated with the OutputBuiltinRunner's base address.
    /// If the information is unavailable, it returns MemoryError.MissingSegmentUsedSizes.
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !u32 {
        return try self.getUsedCells(segments);
    }

    pub fn deduceMemoryCell(
        self: *const Self,
        address: Relocatable,
        memory: *Memory,
    ) ?MaybeRelocatable {
        _ = memory;
        _ = address;
        _ = self;
        return null;
    }
};

test "OutputBuiltinRunner: init should init an OutputBuiltinRunner instance" {
    try expectEqual(
        OutputBuiltinRunner{
            .base = 0,
            .stop_ptr = null,
            .included = true,
        },
        OutputBuiltinRunner.init(true),
    );
    try expectEqual(
        OutputBuiltinRunner{
            .base = 0,
            .stop_ptr = null,
            .included = false,
        },
        OutputBuiltinRunner.init(false),
    );
}

test "OutputBuiltinRunner: initializeSegments should set builtin base to segment index" {
    var output_builtin = OutputBuiltinRunner.init(true);
    const memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    _ = try memory_segment_manager.addSegment();
    try output_builtin.initializeSegments(memory_segment_manager);
    try expectEqual(
        @as(usize, 1),
        output_builtin.base,
    );
}

test "OutputBuiltinRunner: initialStack should return an empty array list if included is false" {
    var output_builtin = OutputBuiltinRunner.init(false);
    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer expected.deinit();
    var actual = try output_builtin.initialStack(std.testing.allocator);
    defer actual.deinit();
    try expectEqual(
        expected,
        actual,
    );
}

test "OutputBuiltinRunner: initialStack should return an a proper array list if included is true" {
    var output_builtin = OutputBuiltinRunner.init(true);
    output_builtin.base = 10;
    var expected = ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try expected.append(.{ .relocatable = .{
        .segment_index = 10,
        .offset = 0,
    } });
    defer expected.deinit();
    var actual = try output_builtin.initialStack(std.testing.allocator);
    defer actual.deinit();
    try expectEqualSlices(
        MaybeRelocatable,
        expected.items,
        actual.items,
    );
}

test "OutputBuiltinRunner: getUsedCells should return memory error if segment used size is null" {
    var output_builtin = OutputBuiltinRunner.init(true);
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        output_builtin.getUsedCells(memory_segment_manager),
    );
}

test "OutputBuiltinRunner: getUsedCells should return the number of used cells" {
    var output_builtin = OutputBuiltinRunner.init(true);
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(0, 10);
    try expectEqual(
        @as(
            u32,
            @intCast(10),
        ),
        try output_builtin.getUsedCells(memory_segment_manager),
    );
}

test "OutputBuiltinRunner: getUsedInstances should return memory error if segment used size is null" {
    var output_builtin = OutputBuiltinRunner.init(true);
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        output_builtin.getUsedInstances(memory_segment_manager),
    );
}

test "OutputBuiltinRunner: getUsedInstances should return the number of used instances" {
    var output_builtin = OutputBuiltinRunner.init(true);
    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(0, 345);
    try expectEqual(
        @as(u32, @intCast(345)),
        try output_builtin.getUsedInstances(memory_segment_manager),
    );
}
