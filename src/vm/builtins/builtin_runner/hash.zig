const std = @import("std");
const pedersen_instance_def = @import("../../types/pedersen_instance_def.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const HashBuiltinRunner = struct {
    const Self = @This();

    base: usize,
    ratio: ?u32,
    cells_per_instance: u32,
    n_input_cells: u32,
    stop_ptr: ?usize,
    included: bool,
    instances_per_component: u32,
    verified_addresses: ArrayList(bool),

    pub fn new(
        allocator: Allocator,
        ratio: ?u32,
        included: bool,
    ) Self {
        return .{
            .base = 0,
            .ratio = ratio,
            .cell_per_instance = pedersen_instance_def.CELLS_PER_HASH,
            .n_input_cells = pedersen_instance_def.INPUT_CELLS_PER_HASH,
            .stop_ptr = null,
            .included = included,
            .instances_per_component = 1,
            .verified_addresses = ArrayList(bool).init(allocator),
        };
    }
};
