const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Number of cells by bitwise operation
pub const CELLS_PER_BITWISE: u32 = 5;
/// Number of input cells by bitwise operation
pub const INPUT_CELLS_PER_BITWISE: u32 = 2;
/// Default total number of bits for BitwiseInstanceDef.
pub const TOTAL_N_BITS_BITWISE_DEFAULT = 251;

/// Represents a Bitwise Instance Definition.
pub const BitwiseInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32 = 256,
    /// The number of bits in a single field element that are supported by the bitwise builtin.
    total_n_bits: u32 = TOTAL_N_BITS_BITWISE_DEFAULT,

    /// Initializes a new Bitwise Instance Definition with optional ratio.
    ///
    /// # Parameters
    ///
    /// - `ratio`: An optional parameter representing the ratio.
    ///
    /// # Returns
    ///
    /// A new `BitwiseInstanceDef` instance with the specified configuration.
    pub fn init(ratio: ?u32) Self {
        return .{ .ratio = ratio };
    }

    /// Gets the number of cells used by the bitwise operation.
    ///
    /// # Parameters
    ///
    /// - `self`: A pointer to the BitwiseInstanceDef.
    ///
    /// # Returns
    ///
    /// The number of cells used by the bitwise operation.
    pub fn cellsPerBuiltin(_: *const Self) u32 {
        return CELLS_PER_BITWISE;
    }

    /// Performs a range check on the number of units per builtin for the bitwise operation.
    ///
    /// # Parameters
    ///
    /// - `self`: A pointer to the BitwiseInstanceDef.
    ///
    /// # Returns
    ///
    /// Always returns 0 for the bitwise operation.
    pub fn rangeCheckUnitsPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "BitwiseInstanceDef: init should initialize a BitwiseInstanceDef instance with the given ratio" {
    // Create an expected BitwiseInstanceDef instance with specified ratio and total_n_bits.
    const expected_instance = BitwiseInstanceDef{ .ratio = 34, .total_n_bits = 251 };

    // Initialize a BitwiseInstanceDef instance with the specified ratio using the init function.
    const initialized_instance = BitwiseInstanceDef.init(34);

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}

test "BitwiseInstanceDef: cellsPerBuiltin should return the number of cells by bitwise operation" {
    // Initialize a BitwiseInstanceDef instance with a specified ratio.
    const bitwiseInstanceDef = BitwiseInstanceDef.init(34);

    // Call the cellsPerBuiltin method and ensure it returns the expected number of cells.
    try expectEqual(5, bitwiseInstanceDef.cellsPerBuiltin());
}

test "BitwiseInstanceDef: rangeCheckUnitsPerBuiltin should return zero" {
    // Initialize a BitwiseInstanceDef instance with a specified ratio.
    const bitwiseInstanceDef = BitwiseInstanceDef.init(34);

    // Call the rangeCheckUnitsPerBuiltin method and ensure it returns zero.
    try expectEqual(0, bitwiseInstanceDef.rangeCheckUnitsPerBuiltin());
}
