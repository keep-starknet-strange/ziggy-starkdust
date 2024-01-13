const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Represents the number of cells in each EC operation P + m * Q = R, which is 7 cells.
/// These cells are: P_x, P_y, Q_x, Q_y, m, R_x, R_y.
pub const CELLS_PER_EC_OP: u32 = 7;

/// Represents the number of input cells per EC operation, which is 5 cells.
/// These cells are: P_x, P_y, Q_x, Q_y, m.
pub const INPUT_CELLS_PER_EC_OP: u32 = 5;

/// Represents an EC Operation Instance Definition.
pub const EcOpInstanceDef = struct {
    const Self = @This();

    /// The ratio associated with the instance.
    ratio: ?u32 = 256,
    /// The height of the scalar in bits.
    scalar_height: u32 = 256,
    /// The number of bits in the scalar.
    scalar_bits: u32 = 252,

    /// Initializes an instance with the specified ratio.
    ///
    /// Arguments:
    /// - `ratio`: The ratio to associate with the instance.
    ///
    /// Returns:
    /// An instance of EC Operation Definition with the specified ratio.
    pub fn init(ratio: ?u32) Self {
        return .{ .ratio = ratio };
    }

    /// Retrieves the number of cells per built-in EC operation.
    ///
    /// Arguments:
    /// - `self`: Pointer to the EC Operation Instance Definition.
    ///
    /// Returns:
    /// The number of cells per built-in EC operation.
    pub fn cellsPerBuiltin(_: *const Self) u32 {
        return CELLS_PER_EC_OP;
    }

    /// Retrieves the number of range check units per built-in EC operation.
    ///
    /// Arguments:
    /// - `self`: Pointer to the EC Operation Instance Definition.
    ///
    /// Returns:
    /// The number of range check units per built-in EC operation.
    pub fn rangeCheckUnitsPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "EcOpInstanceDef: init function should return an EcOp instance def with provided ratio" {
    // Define the expected EcOpInstanceDef with specified ratio.
    const expected_instance = EcOpInstanceDef{
        .ratio = 8,
        .scalar_height = 256,
        .scalar_bits = 252,
    };

    // Initialize a new EcOpInstanceDef using the init function with the specified ratio.
    const initialized_instance = EcOpInstanceDef.init(8);

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}

test "EcOpInstanceDef: initDefault function should return the default EcOp instance def" {
    // Define the expected EcOpInstanceDef with default values.
    const expected_instance = EcOpInstanceDef{
        .ratio = 256,
        .scalar_height = 256,
        .scalar_bits = 252,
    };

    // Initialize a new EcOpInstanceDef using the default init function.
    const initialized_instance = EcOpInstanceDef{};

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}

test "EcOpInstanceDef: cellsPerBuiltin function should return CELLS_PER_EC_OP" {
    // Initialize a default EcOpInstanceDef.
    const defaut_instance_def = EcOpInstanceDef{};

    // Call the cellsPerBuiltin method and ensure it returns the expected number of cells.
    try expectEqual(CELLS_PER_EC_OP, defaut_instance_def.cellsPerBuiltin());
}

test "EcOpInstanceDef: rangeCheckUnitsPerBuiltin function should return 0" {
    // Initialize a default EcOpInstanceDef.
    const defaut_instance_def = EcOpInstanceDef{};

    // Call the rangeCheckUnitsPerBuiltin method and ensure it returns zero.
    try expectEqual(0, defaut_instance_def.rangeCheckUnitsPerBuiltin());
}
