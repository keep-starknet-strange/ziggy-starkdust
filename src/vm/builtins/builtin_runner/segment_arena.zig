const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;

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
    base: Relocatable,
    /// Included boolean flag
    included: bool,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells per instance
    n_input_cells_per_instance: u32,
    /// Stop pointer
    stop_ptr: ?usize,

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
    pub fn new(included: bool) Self {
        return .{
            .base = Relocatable.default(),
            .included = included,
            .cell_per_instance = ARENA_BUILTIN_SIZE,
            .n_input_cells_per_instance = ARENA_BUILTIN_SIZE,
            .stop_ptr = null,
        };
    }

    /// Get the base segment index of this segment arena runner.
    ///
    /// # Returns
    ///
    /// The base segment index as a `usize`.
    pub fn getBase(self: *const Self) usize {
        return @as(
            usize,
            @intCast(self.base.segment_index),
        );
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
