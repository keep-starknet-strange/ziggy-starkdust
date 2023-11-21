const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const relocatable = @import("../../memory/relocatable.zig");
const Error = @import("../../error.zig");
const validation_rule = @import("../../memory/memory.zig").validation_rule;
const Memory = @import("../../memory/memory.zig").Memory;
const range_check_instance_def = @import("../../types/range_check_instance_def.zig");

const CELLS_PER_RANGE_CHECK = range_check_instance_def.CELLS_PER_RANGE_CHECK;
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
        const bound: Felt252 = Felt252.one().saturating_shl(16 * n_parts);
        const _bound: ?Felt252 = if (n_parts != 0 and bound.isZero()) null else bound;

        return .{
            .ratio = ratio,
            .base = 0,
            .stop_ptr = null,
            .cells_per_instance = CELLS_PER_RANGE_CHECK,
            .n_input_cells = CELLS_PER_RANGE_CHECK,
            ._bound = _bound,
            .included = included,
            .n_parts = n_parts,
            .instances_per_component = 1,
        };
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
    pub fn initializeSegments(self: *Self, segments: *MemorySegmentManager) void {
        self.base = @intCast(segments.addSegment().segment_index);
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
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
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
    pub fn getUsedCells(self: *const Self, segments: *MemorySegmentManager) !u32 {
        return segments.getSegmentUsedSize(
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
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !usize {
        return std.math.divCeil(
            usize,
            try self.getUsedCells(segments),
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
    pub fn getMemorySegmentAddresses(self: *Self) std.meta.Tuple(&.{
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
    pub fn finalStack(
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

            if (stop_ptr != try self.getUsedInstances(segments) * @as(
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

    /// Creates Validation Rules ArrayList
    ///
    /// # Parameters
    ///
    /// - `memory`: A `Memory` pointer of validation rules segment index.
    /// - `address`: A `Relocatable` pointer to the validation rule.
    ///
    /// # Returns
    ///
    /// An `ArrayList(Relocatable)` containing the rules address
    /// verification fails.
    pub fn rangeCheckValidationRule(memory: *Memory, address: Relocatable) ?[]const Relocatable {
        const num = ((memory.get(address) catch {
            return null;
        }) orelse {
            return null;
        }).tryIntoFelt() catch {
            return null;
        };

        if (@bitSizeOf(u256) - @clz(num.toInteger()) <= N_PARTS * INNER_RC_BOUND_SHIFT) {
            // TODO: unit tests
            return &[_]Relocatable{address};
        } else {
            return null;
        }
    }

    /// Creates Validation Rule in Memory
    ///
    /// # Parameters
    ///
    /// - `memory`: A `Memory` pointer of validation rules segment index.
    ///
    /// # Modifies
    ///
    /// - `memory`: Adds validation rule to `memory`.
    pub fn addValidationRule(self: *const Self, memory: *Memory) !void {
        try memory.addValidationRule(@intCast(self.base), rangeCheckValidationRule);
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

test "initialize segments for range check" {

    // given
    const builtin = RangeCheckBuiltinRunner.new(8, 8, true);
    const allocator = std.testing.allocator;
    var mem = try MemorySegmentManager.init(allocator);
    defer mem.deinit();

    // assert
    try std.testing.expectEqual(
        builtin.base,
        0,
    );
}

test "used instances" {
    // given
    var builtin = RangeCheckBuiltinRunner.new(10, 12, true);

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();
    try memory_segment_manager.segment_used_sizes.put(0, 1);
    try std.testing.expectEqual(
        @as(usize, @intCast(1)),
        try builtin.getUsedInstances(memory_segment_manager),
    );
}
