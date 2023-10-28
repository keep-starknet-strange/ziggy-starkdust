const bitwise_instance_def = @import("../../types/bitwise_instance_def.zig");

pub const BitwiseBuiltinRunner = struct {
    const Self = @This();

    ratio: ?u32,
    base: usize,
    cells_per_instance: u32,
    n_input_cells: u32,
    bitwise_builtin: bitwise_instance_def.BitwiseInstanceDef,
    stop_ptr: ?usize,
    included: bool,
    instances_per_component: u32,

    pub fn new(
        instance_def: *bitwise_instance_def.BitwiseInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .base = 0,
            .cell_per_instance = bitwise_instance_def.CELLS_PER_BITWISE,
            .n_input_cells = bitwise_instance_def.INPUT_CELLS_PER_BITWISE,
            .bitwise_builtin = instance_def,
            .stop_ptr = null,
            .included = included,
            .instances_per_component = 1,
        };
    }

    pub fn get_base(self: *const Self) usize {
        return self.base;
    }
};
