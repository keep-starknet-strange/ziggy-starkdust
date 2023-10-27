const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const range_check_instance_def = @import("../../types/range_check_instance_def.zig");

pub const RangeCheckBuiltinRunner = struct {
    const Self = @This();

    ratio: ?u32,
    base: usize,
    stop_ptr: ?usize,
    cells_per_instance: u32,
    n_input_cells: u32,
    _bound: ?Felt252,
    included: bool,
    n_parts: u32,
    instances_per_component: u32,

    pub fn new(
        ratio: ?u32,
        n_parts: u32,
        included: bool,
    ) Self {
        return .{
            .ratio = ratio,
            .base = 0,
            .stop_ptr = null,
            .cell_per_instance = range_check_instance_def.CELLS_PER_RANGE_CHECK,
            .n_input_cells = range_check_instance_def.CELLS_PER_RANGE_CHECK,
            // TODO: implement shl logic: https://github.com/lambdaclass/cairo-vm/blob/e6171d66a64146acc16d5512766ae91ae044f297/vm/src/vm/runners/builtin_runner/range_check.rs#L48-L53
            ._bound = null,
            .included = included,
            .n_parts = n_parts,
            .instances_per_component = 1,
        };
    }

    pub fn get_base(self: *Self) usize {
        return self.base;
    }
};
