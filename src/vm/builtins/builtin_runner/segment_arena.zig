const relocatable = @import("../../memory/relocatable.zig");

const ARENA_BUILTIN_SIZE: u32 = 3;
// The size of the builtin segment at the time of its creation.
const INITIAL_SEGMENT_SIZE: usize = @as(
    usize,
    ARENA_BUILTIN_SIZE,
);

pub const SegmentArenaBuiltinRunner = struct {
    const Self = @This();

    base: relocatable.Relocatable,
    included: bool,
    cells_per_instance: u32,
    n_input_cells_per_instance: u32,
    stop_ptr: ?usize,

    pub fn new(included: bool) Self {
        return .{
            .base = relocatable.Relocatable.default(),
            .included = included,
            .cell_per_instance = ARENA_BUILTIN_SIZE,
            .n_input_cells_per_instance = ARENA_BUILTIN_SIZE,
            .stop_ptr = null,
        };
    }

    pub fn get_base(self: *const Self) usize {
        return @as(
            usize,
            self.base.segment_index,
        );
    }
};
