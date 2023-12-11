const std = @import("std");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;

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
