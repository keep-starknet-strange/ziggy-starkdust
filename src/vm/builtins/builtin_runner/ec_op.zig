const std = @import("std");
const ec_op_instance_def = @import("../../types/ec_op_instance_def.zig");
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;

const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

pub const EcOpBuiltinRunner = struct {
    const Self = @This();

    ratio: ?u32,
    base: usize,
    cells_per_instance: u32,
    n_input_cells: u32,
    ec_op_builtin: ec_op_instance_def.EcOpInstanceDef,
    stop_ptr: ?usize,
    included: bool,
    instances_per_component: u32,
    cache: AutoHashMap(relocatable.Relocatable, Felt252),

    pub fn new(
        allocator: Allocator,
        instance_def: *ec_op_instance_def.EcOpInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .base = 0,
            .n_input_cells = ec_op_instance_def.INPUT_CELLS_PER_EC_OP,
            .cell_per_instance = ec_op_instance_def.CELLS_PER_EC_OP,
            .ec_op_builtin = instance_def,
            .stop_ptr = null,
            .included = included,
            .instances_per_component = 1,
            .cache = AutoHashMap(relocatable.Relocatable, Felt252).init(allocator),
        };
    }
};
