const std = @import("std");
const pedersen_instance_def = @import("../../types/pedersen_instance_def.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Hash built-in runner
pub const HashBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: usize = 0,
    /// Ratio
    ratio: ?u32,
    /// Number of cells per instance
    cells_per_instance: u32 = pedersen_instance_def.CELLS_PER_HASH,
    /// Number of input cells
    n_input_cells: u32 = pedersen_instance_def.INPUT_CELLS_PER_HASH,
    /// Stop pointer
    stop_ptr: ?usize = null,
    /// Included boolean flag
    included: bool,
    /// Number of instance per component
    instances_per_component: u32 = 1,
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
            .ratio = ratio,
            .included = included,
            .verified_addresses = ArrayList(bool).init(allocator),
        };
    }

    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        _ = self;
        _ = segments;
    }

    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        _ = self;
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();
        return result;
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
