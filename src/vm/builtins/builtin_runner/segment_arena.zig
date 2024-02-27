const std = @import("std");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// Arena builtin size
const ARENA_BUILTIN_SIZE: u32 = 3;
// The size of the builtin segment at the time of its creation.
const INITIAL_SEGMENT_SIZE: usize = @as(
    usize,
    @intCast(ARENA_BUILTIN_SIZE),
);

/// Segment Arena built-in runner
pub const SegmentArenaBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: Relocatable = .{},
    /// Included boolean flag
    included: bool,
    /// Number of cells per instance
    cells_per_instance: u32 = ARENA_BUILTIN_SIZE,
    /// Number of input cells per instance
    n_input_cells_per_instance: u32 = ARENA_BUILTIN_SIZE,
    /// Stop pointer
    stop_ptr: ?usize = null,

    /// Create a new SegmentArenaBuiltinRunner instance.
    ///
    /// This function initializes a new `SegmentArenaBuiltinRunner` instance with the provided `included` value.
    ///
    /// # Arguments
    ///
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `SegmentArenaBuiltinRunner` instance.
    pub fn init(included: bool) Self {
        return .{ .included = included };
    }

    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        _ = self;
        _ = segments;
    }

    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        _ = self;
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();
        return result;
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
