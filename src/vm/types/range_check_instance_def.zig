const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Number of cells per range check
pub const CELLS_PER_RANGE_CHECK: u32 = 1;

/// Represents a Range Check Instance Definition.
pub const RangeCheckInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32 = 8,
    /// Number of 16-bit range checks that will be used for each instance of the builtin.
    ///
    /// For example, n_parts=8 defines the range [0, 2^128).
    n_parts: u32 = 8,

    /// Creates a new instance of `RangeCheckInstanceDef` with the specified ratio and n_parts representation.
    ///
    /// # Parameters
    ///
    /// - `ratio`: An optional 32-bit integer representing the ratio for the Range check instance.
    /// - `n_parts`: An 32-bit integer representing the number of parts.
    ///
    /// # Returns
    ///
    /// A new `RangeCheckInstanceDef` instance with the specified parameters.
    pub fn init(ratio: ?u32, n_parts: u32) Self {
        return .{ .ratio = ratio, .n_parts = n_parts };
    }

    /// Retrieves the number of cells per built-in Range Check operation.
    ///
    /// # Parameters
    ///
    /// - `self`: Pointer to the Range Check Instance Definition.
    ///
    /// # Returns
    ///
    /// The number of cells per built-in Range Check operation.
    pub fn cellsPerBuiltin(_: *const Self) u32 {
        return CELLS_PER_RANGE_CHECK;
    }

    /// Retrieves the number of range check units per built-in Range Check operation.
    ///
    /// # Parameters
    ///
    /// - `self`: Pointer to the Range Check Instance Definition.
    ///
    /// # Returns
    ///
    /// The number of range check units per built-in Range Check operation.
    pub fn rangeCheckUnitsPerBuiltin(self: *const Self) u32 {
        return self.n_parts;
    }
};

test "RangeCheckInstanceDef: test default initialization" {
    // Define the expected RangeCheckInstanceDef with default values.
    const expected_instance = RangeCheckInstanceDef{ .ratio = 8, .n_parts = 8 };

    // Initialize a default RangeCheckInstanceDef.
    const default_instance = RangeCheckInstanceDef{};

    // Ensure that the default instance matches the expected instance.
    try expectEqual(expected_instance, default_instance);
}

test "RangeCheckInstanceDef: test initialization from provided parameters" {
    // Initialize a new RangeCheckInstanceDef using the init function with specific values.
    const result = RangeCheckInstanceDef.init(3, 3);

    // Define the expected RangeCheckInstanceDef with specific values.
    const expected_instance = RangeCheckInstanceDef{ .ratio = 3, .n_parts = 3 };

    // Ensure that the initialized instance matches the expected instance.
    try expectEqual(expected_instance, result);
}

test "RangeCheckInstanceDef: cellsPerBuiltin should return the number of cells per range check" {
    // Initialize a default RangeCheckInstanceDef.
    const range_check_instance = RangeCheckInstanceDef{};

    // Call the cellsPerBuiltin method and ensure it returns the expected number of cells.
    try expectEqual(
        @as(u32, 1),
        range_check_instance.cellsPerBuiltin(),
    );
}

test "RangeCheckInstanceDef: rangeCheckUnitsPerBuiltin returns the count of units for each Range Check operation" {
    // Initialize a default RangeCheckInstanceDef.
    const range_check_instance = RangeCheckInstanceDef{};

    // Call the rangeCheckUnitsPerBuiltin method and ensure it returns the expected number of range checks.
    try expectEqual(
        @as(u32, 8),
        range_check_instance.rangeCheckUnitsPerBuiltin(),
    );
}
