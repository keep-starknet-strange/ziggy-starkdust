const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const range_check_instance_def = @import("../../types/range_check_instance_def.zig");

/// Range check built-in runner
pub const RangeCheckBuiltinRunner = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells
    n_input_cells: u32,
    /// Felt252 field element bound
    _bound: ?Felt252,
    /// Included boolean flag
    included: bool,
    /// Number of parts
    n_parts: u32,
    /// Number of instances per component
    instances_per_component: u32,

    /// Create a new RangeCheckBuiltinRunner instance.
    ///
    /// This function initializes a new `RangeCheckBuiltinRunner` instance with the provided
    /// `ratio`, `n_parts`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `ratio`: An optional 32-bit unsigned integer representing the ratio.
    /// - `n_parts`: The number of parts for range check operations.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `RangeCheckBuiltinRunner` instance.
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

    /// Get the base value of this range check runner.
    ///
    /// # Returns
    ///
    /// The base value as a `usize`.
    pub fn get_base(self: *const Self) usize {
        return self.base;
    }
};
