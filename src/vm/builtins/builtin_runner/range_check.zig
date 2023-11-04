const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const range_check_instance_def = @import("../../types/range_check_instance_def.zig");
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const relocatable = @import("../../memory/relocatable.zig");
const Error = @import("../../error.zig");
const validation_rule = @import("../../memory/memory.zig").validation_rule;
const Memory = @import("../../memory/memory.zig").Memory;
const Field = @import("../../../math/fields/starknet.zig").Field;

const Relocatable = relocatable.Relocatable;
const MaybeRelocatable = relocatable.MaybeRelocatable;
const MemoryError = Error.MemoryError;
const RunnerError = Error.RunnerError;

const N_PARTS: u64 = 8;
const INNER_RC_BOUND_SHIFT: u64 = 16;

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
        const bound = Felt252.one().overflowing_shl(16 * n_parts);
        const _bound: ?Felt252 = if (n_parts != 0 and bound.zero()) null else Felt252.new(bound);

        return .{
            .ratio = ratio,
            .base = 0,
            .stop_ptr = null,
            .cell_per_instance = range_check_instance_def.CELLS_PER_RANGE_CHECK,
            .n_input_cells = range_check_instance_def.CELLS_PER_RANGE_CHECK,
            ._bound = _bound,
            .included = included,
            .n_parts = n_parts,
            .instances_per_component = 1,
        };
    }

    /// Get the base value of this Range Check runner.
    ///
    /// # Returns
    ///
    /// The base value as a `usize`.
    pub fn get_base(self: *const Self) usize {
        return self.base;
    }

    /// Get the ratio value of this Range Check runner.
    ///
    /// # Returns
    ///
    /// The ratio value as an `u32`.
    pub fn get_ratio(self: *const Self) ?u32 {
        return self.ratio;
    }

    /// Initializes memory segments and sets the base value for the Range Check runner.
    ///
    /// This function adds a memory segment using the provided `segments` manager and
    /// sets the `base` value to the index of the new segment.
    ///
    /// # Parameters
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment management.
    ///
    /// # Modifies
    /// - `self`: Updates the `base` value to the new segment's index.
    pub fn initialize_segments(self: *Self, segments: *MemorySegmentManager) void {
        self.base = segments.add().segment_index;
    }

    /// Initializes and returns an `ArrayList` of `MaybeRelocatable` values.
    ///
    /// If the range check runner is included, it appends a `Relocatable` element to the `ArrayList`
    /// with the base value. Otherwise, it returns an empty `ArrayList`.
    ///
    /// # Parameters
    /// - `allocator`: An allocator for initializing the `ArrayList`.
    ///
    /// # Returns
    /// An `ArrayList` of `MaybeRelocatable` values.
    pub fn initial_stack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        if (self.included) {
            try result.append(.{
                .relocatable = Relocatable.new(
                    @intCast(self.base),
                    0,
                ),
            });
            return result;
        }
        return result;
    }

    /// Get the number of used cells associated with this Range Check runner.
    ///
    /// # Parameters
    ///
    /// - `segments`: A pointer to a `MemorySegmentManager` for segment size information.
    ///
    /// # Returns
    ///
    /// The number of used cells as a `u32`, or `MemoryError.MissingSegmentUsedSizes` if
    /// the size is not available.
    pub fn get_used_cells(self: *const Self, segments: *MemorySegmentManager) !u32 {
        return segments.get_segment_used_size(
            @intCast(self.base),
        ) orelse MemoryError.MissingSegmentUsedSizes;
    }

    /// Calculates the number of used instances for the Range Check runner.
    ///
    /// This function computes the number of used instances based on the available
    /// used cells and the number of cells per instance. It performs a ceiling division
    /// to ensure that any remaining cells are counted as an additional instance.
    ///
    /// # Parameters
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment information.
    ///
    /// # Returns
    /// The number of used instances as a `usize`.
    pub fn get_used_instances(self: *Self, segments: *MemorySegmentManager) !usize {
        return std.math.divCeil(
            usize,
            try self.get_used_cells(segments),
            @intCast(self.cells_per_instance),
        );
    }

    /// Retrieves memory segment addresses as a tuple.
    ///
    /// Returns a tuple containing the `base` and `stop_ptr` addresses associated
    /// with the Range Check runner's memory segments. The `stop_ptr` may be `null`.
    ///
    /// # Returns
    /// A tuple of `usize` and `?usize` addresses.
    pub fn get_memory_segment_addresses(self: *Self) std.meta.Tuple(&.{
        usize,
        ?usize,
    }) {
        return .{
            self.base,
            self.stop_ptr,
        };
    }

    /// Calculate the final stack.
    ///
    /// This function calculates the final stack pointer for the Range Check runner, based on the provided `segments`, `pointer`, and `self` settings. If the runner is included,
    /// it verifies the stop pointer for consistency and sets it. Otherwise, it sets the stop pointer to zero.
    ///
    /// # Parameters
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment management.
    /// - `pointer`: A `Relocatable` pointer to the current stack pointer.
    ///
    /// # Returns
    ///
    /// A `Relocatable` pointer to the final stack pointer, or an error code if the
    /// verification fails.
    pub fn final_stack(
        self: *Self,
        segments: *MemorySegmentManager,
        pointer: Relocatable,
    ) !Relocatable {
        if (self.included) {
            const stop_pointer_addr = pointer.subUint(
                @intCast(1),
            ) catch return RunnerError.NoStopPointer;
            const stop_pointer = try (segments.memory.get(
                stop_pointer_addr,
            ) catch return RunnerError.NoStopPointer).tryIntoRelocatable();
            if (@as(
                isize,
                @intCast(self.base),
            ) != stop_pointer.segment_index) {
                return RunnerError.InvalidStopPointerIndex;
            }
            const stop_ptr = stop_pointer.offset;

            if (stop_ptr != try self.get_used_instances(segments) * @as(
                usize,
                @intCast(self.cells_per_instance),
            )) {
                return RunnerError.InvalidStopPointer;
            }
            self.stop_ptr = stop_ptr;
            return stop_pointer_addr;
        }

        self.stop_ptr = 0;
        return pointer;
    }

    pub fn range_check_validation_rule(memory: *Memory, address: Relocatable) std.ArrayList(!Relocatable) {
        const addr = memory.get(address);
        if (addr.bits <= N_PARTS * INNER_RC_BOUND_SHIFT) {
            return std.ArrayList.append(address);
        } else {
            return std.ArrayList.append(Error.MemoryOutOfBounds);
        }
    }

    pub fn add_validation_rule(self: *const Self, memory: *Memory) void {
        memory.add_validation_rule(self.base.segment_index, range_check_validation_rule);
    }
};
