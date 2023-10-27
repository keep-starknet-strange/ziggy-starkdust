const std = @import("std");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const relocatable = @import("../../memory/relocatable.zig");
const keccak_instance_def = @import("../../types/keccak_instance_def.zig");

const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

pub const KeccakBuiltinRunner = struct {
    const Self = @This();

    ratio: ?u32,
    base: usize,
    cells_per_instance: u32,
    n_input_cells: u32,
    stop_ptr: usize,
    included: bool,
    state_rep: ArrayList(u32),
    instances_per_component: u32,
    cache: AutoHashMap(relocatable.Relocatable, Felt252),

    pub fn new(
        allocator: Allocator,
        instance_def: *keccak_instance_def.KeccakInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .base = 0,
            .n_input_cells = @as(u32, instance_def._state_rep.items.len),
            .cell_per_instance = instance_def.cells_per_builtin(),
            .stop_ptr = null,
            .included = included,
            .state_rep = instance_def._state_rep,
            .instances_per_component = instance_def._instance_per_component,
            .cache = AutoHashMap(relocatable.Relocatable, Felt252).init(allocator),
        };
    }
};
