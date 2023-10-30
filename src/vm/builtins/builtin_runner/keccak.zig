const std = @import("std");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const relocatable = @import("../../memory/relocatable.zig");
const keccak_instance_def = @import("../../types/keccak_instance_def.zig");

const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

/// Keccak built-in runner
pub const KeccakBuiltinRunner = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells
    n_input_cells: u32,
    /// Stop pointer
    stop_ptr: usize,
    /// Included boolean flag
    included: bool,
    state_rep: ArrayList(u32),
    /// Number of instances per component
    instances_per_component: u32,
    /// Cache
    ///
    /// Hashmap between an address in some memory segment and `Felt252` field element
    cache: AutoHashMap(relocatable.Relocatable, Felt252),

    /// Create a new KeccakBuiltinRunner instance.
    ///
    /// This function initializes a new `KeccakBuiltinRunner` instance with the provided
    /// `allocator`, `instance_def`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the cache.
    /// - `instance_def`: A pointer to the `KeccakInstanceDef` for this runner.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `KeccakBuiltinRunner` instance.
    pub fn new(
        allocator: Allocator,
        instance_def: *keccak_instance_def.KeccakInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .base = 0,
            .n_input_cells = @as(
                u32,
                @intCast(instance_def._state_rep.items.len),
            ),
            .cell_per_instance = instance_def.cells_per_builtin(),
            .stop_ptr = null,
            .included = included,
            .state_rep = instance_def._state_rep,
            .instances_per_component = instance_def._instance_per_component,
            .cache = AutoHashMap(relocatable.Relocatable, Felt252).init(allocator),
        };
    }

    /// Get the base value of this Keccak runner.
    ///
    /// # Returns
    ///
    /// The base value as a `usize`.
    pub fn get_base(self: *const Self) usize {
        return self.base;
    }
};
