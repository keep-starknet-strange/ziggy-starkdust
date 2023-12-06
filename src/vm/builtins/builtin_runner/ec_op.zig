const std = @import("std");
const ec_op_instance_def = @import("../../types/ec_op_instance_def.zig");
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;

const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

/// EC Operation built-in runner
pub const EcOpBuiltinRunner = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells
    n_input_cells: u32,
    /// Built-in EC Operation instance
    ec_op_builtin: ec_op_instance_def.EcOpInstanceDef,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,
    /// Number of instance per component
    instances_per_component: u32,
    /// Cache
    cache: AutoHashMap(Relocatable, Felt252),

    /// Create a new ECOpBuiltinRunner instance.
    ///
    /// This function initializes a new `EcOpBuiltinRunner` instance with the provided
    /// `allocator`, `instance_def`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the cache.
    /// - `instance_def`: A pointer to the `EcOpInstanceDef` for this runner.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `EcOpBuiltinRunner` instance.
    pub fn init(
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
            .cache = AutoHashMap(Relocatable, Felt252).init(allocator),
        };
    }

    pub fn deduceMemoryCell(
        self: *const Self,
        address: Relocatable,
        memory: *Memory,
    ) ?MaybeRelocatable {
        _ = memory;
        _ = address;
        _ = self;
        return null;
    }
};
