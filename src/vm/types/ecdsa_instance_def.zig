const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Each signature consists of 2 cells (a public key and a message).
pub const CELLS_PER_SIGNATURE: u32 = 2;
/// Number of input cells per signature.
pub const INPUTCELLS_PER_SIGNATURE: u32 = 2;

/// Represents an ECDSA Instance Definition.
pub const EcdsaInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32 = 512,
    /// Split to this many different components - for optimization.
    repetitions: u32 = 1,
    /// Size of hash.
    height: u32 = 256,
    /// Number of hash bits
    n_hash_bits: u32 = 251,

    /// Initializes an ECDSA Instance Definition with a specified ratio.
    pub fn init(ratio: ?u32) Self {
        return .{ .ratio = ratio };
    }

    /// Retrieves the number of cells per ECDSA builtin.
    ///
    /// Arguments:
    /// - `self`: Pointer to the ECDSA Instance Definition.
    ///
    /// Returns:
    /// The number of cells per ECDSA signature.
    pub fn cellsPerBuiltin(_: *const Self) u32 {
        return CELLS_PER_SIGNATURE;
    }

    /// Retrieves the range check units per ECDSA builtin.
    ///
    /// Arguments:
    /// - `self`: Pointer to the ECDSA Instance Definition.
    ///
    /// Returns:
    /// The number of range check units per ECDSA signature.
    pub fn rangeCheckUnitsPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "EcdsaInstanceDef: init should return an ECDSA instance def with provided ratio" {
    // Define the expected EcdsaInstanceDef with specified ratio.
    const expected_instance = EcdsaInstanceDef{
        .ratio = 8,
        .repetitions = 1,
        .height = 256,
        .n_hash_bits = 251,
    };

    // Initialize a new EcdsaInstanceDef using the init function with the specified ratio.
    const initialized_instance = EcdsaInstanceDef.init(8);

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}

test "EcdsaInstanceDef: initDefault should return a default ECDSA instance def" {
    // Define the expected EcdsaInstanceDef with default values.
    const expected_instance = EcdsaInstanceDef{
        .ratio = 512,
        .repetitions = 1,
        .height = 256,
        .n_hash_bits = 251,
    };

    // Initialize a new EcdsaInstanceDef using the default init function.
    const initialized_instance = EcdsaInstanceDef{};

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}

test "EcdsaInstanceDef: cellsPerBuiltin should return the number of cells per signature" {
    // Initialize a default EcdsaInstanceDef.
    const default_instance = EcdsaInstanceDef{};

    // Call the cellsPerBuiltin method and ensure it returns the expected number of cells.
    try expectEqual(CELLS_PER_SIGNATURE, default_instance.cellsPerBuiltin());
}

test "EcdsaInstanceDef: rangeCheckUnitsPerBuiltin should return 0" {
    // Initialize a default EcdsaInstanceDef.
    const default_instance = EcdsaInstanceDef{};

    // Call the rangeCheckUnitsPerBuiltin method and ensure it returns zero.
    try expectEqual(@as(u32, 0), default_instance.rangeCheckUnitsPerBuiltin());
}
