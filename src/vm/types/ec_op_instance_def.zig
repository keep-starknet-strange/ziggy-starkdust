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
    ratio: ?u32,
    /// The height of the scalar in bits.
    scalar_height: u32,
    /// The number of bits in the scalar.
    scalar_bits: u32,

    /// Initializes an instance with default values.
    ///
    /// Returns:
    /// An instance of EC Operation Definition with default values.
    pub fn initDefault() Self {
        return .{
            .ratio = 256,
            .scalar_height = 256,
            .scalar_bits = 252,
        };
    }

    /// Initializes an instance with the specified ratio.
    ///
    /// Arguments:
    /// - `ratio`: The ratio to associate with the instance.
    ///
    /// Returns:
    /// An instance of EC Operation Definition with the specified ratio.
    pub fn init(ratio: ?u32) Self {
        return .{
            .ratio = ratio,
            .scalar_height = 256,
            .scalar_bits = 252,
        };
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
    try expectEqual(
        EcOpInstanceDef{
            .ratio = 8,
            .scalar_height = 256,
            .scalar_bits = 252,
        },
        EcOpInstanceDef.init(8),
    );
}

test "EcOpInstanceDef: initDefault function should return the default EcOp instance def" {
    try expectEqual(
        EcOpInstanceDef{
            .ratio = 256,
            .scalar_height = 256,
            .scalar_bits = 252,
        },
        EcOpInstanceDef.initDefault(),
    );
}

test "EcOpInstanceDef: cellsPerBuiltin function should return CELLS_PER_EC_OP" {
    try expectEqual(
        CELLS_PER_EC_OP,
        EcOpInstanceDef.initDefault().cellsPerBuiltin(),
    );
}

test "EcOpInstanceDef: rangeCheckUnitsPerBuiltin function should return 0" {
    try expectEqual(
        @as(u32, 0),
        EcOpInstanceDef.initDefault().rangeCheckUnitsPerBuiltin(),
    );
}
