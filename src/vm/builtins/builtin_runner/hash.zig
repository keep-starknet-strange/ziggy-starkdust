const std = @import("std");
const pedersen_instance_def = @import("../../types/pedersen_instance_def.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Hash built-in runner
pub const HashBuiltinRunner = struct {
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
    /// Number of instance per component
    instances_per_component: u32,
    /// Vector for verified addresses
    verified_addresses: ArrayList(bool),

    /// Create a new HashBuiltinRunner instance.
    ///
    /// This function initializes a new `HashBuiltinRunner` instance with the provided
    /// `allocator`, `ratio`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the `verified_addresses` list.
    /// - `ratio`: An optional 32-bit unsigned integer representing the ratio.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `HashBuiltinRunner` instance.
    pub fn init(
        allocator: Allocator,
        ratio: ?u32,
        included: bool,
    ) Self {
        return .{
            .base = 0,
            .ratio = ratio,
            .cells_per_instance = pedersen_instance_def.CELLS_PER_HASH,
            .n_input_cells = pedersen_instance_def.INPUT_CELLS_PER_HASH,
            .stop_ptr = null,
            .included = included,
            .instances_per_component = 1,
            .verified_addresses = ArrayList(bool).init(allocator),
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
