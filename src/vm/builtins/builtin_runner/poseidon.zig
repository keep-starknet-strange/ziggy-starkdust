const std = @import("std");
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const poseidon_instance_def = @import("../../types/poseidon_instance_def.zig");

const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

pub const PoseidonBuiltinRunner = struct {
    const Self = @This();

    base: usize,
    ratio: ?u32,
    cells_per_instance: u32,
    n_input_cells: u32,
    stop_ptr: ?usize,
    included: bool,
    cache: AutoHashMap(relocatable.Relocatable, Felt252),
    instances_per_component: u32,

    pub fn new(
        allocator: Allocator,
        ratio: ?u32,
        included: bool,
    ) Self {
        return .{
            .base = 0,
            .ratio = ratio,
            .cell_per_instance = poseidon_instance_def.CELLS_PER_POSEIDON,
            .n_input_cells = poseidon_instance_def.INPUT_CELLS_PER_POSEIDON,
            .stop_ptr = null,
            .included = included,
            .cache = AutoHashMap(relocatable.Relocatable, Felt252).init(allocator),
            .instances_per_component = 1,
        };
    }

    pub fn get_base(self: *const Self) usize {
        return self.base;
    }
};
