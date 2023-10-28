const bitwise_instance_def = @import("../../types/bitwise_instance_def.zig");

/// Bitwise built-in runner
pub const BitwiseBuiltinRunner = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells
    n_input_cells: u32,
    /// Built-in bitwise instance
    bitwise_builtin: bitwise_instance_def.BitwiseInstanceDef,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,
    /// Number of instance per component
    instances_per_component: u32,

    /// Create a new BitwiseBuiltinRunner instance.
    ///
    /// This function initializes a new `BitwiseBuiltinRunner` instance with the provided
    /// `instance_def` and `included` values.
    ///
    /// # Arguments
    ///
    /// - `instance_def`: A pointer to the `BitwiseInstanceDef` for this runner.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `BitwiseBuiltinRunner` instance.
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

    /// Get the base value of this runner.
    ///
    /// # Returns
    ///
    /// The base value as a `usize`.
    pub fn get_base(self: *const Self) usize {
        return self.base;
    }
};
