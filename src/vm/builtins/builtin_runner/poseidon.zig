const std = @import("std");
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const poseidon_instance_def = @import("../../types/poseidon_instance_def.zig");

const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

/// Poseidon built-in runner
pub const PoseidonBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: usize,
    /// Ratio
    ratio: ?u32,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells
    n_input_cells: u32,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,
    /// Cache
    ///
    /// Hashmap between an address in some memory segment and `Felt252` field element
    cache: AutoHashMap(relocatable.Relocatable, Felt252),
    /// Number of instances per component
    instances_per_component: u32,

    /// Create a new PoseidonBuiltinRunner instance.
    ///
    /// This function initializes a new `PoseidonBuiltinRunner` instance with the provided
    /// `allocator`, `ratio`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the cache.
    /// - `ratio`: An optional 32-bit unsigned integer representing the ratio.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `PoseidonBuiltinRunner` instance.
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

    /// Get the base value of this Poseidon runner.
    ///
    /// # Returns
    ///
    /// The base value as a `usize`.
    pub fn getBase(self: *const Self) usize {
        return self.base;
    }
};
