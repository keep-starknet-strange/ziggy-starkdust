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
    ratio: ?u32,
    /// Split to this many different components - for optimization.
    repetitions: u32,
    /// Size of hash.
    height: u32,
    /// Number of hash bits
    n_hash_bits: u32,

    /// Initializes an ECDSA Instance Definition with default values.
    pub fn initDefault() Self {
        return .{
            .ratio = 512,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
    }

    /// Initializes an ECDSA Instance Definition with a specified ratio.
    pub fn init(ratio: ?u32) Self {
        return .{
            .ratio = ratio,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
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
    try expectEqual(
        EcdsaInstanceDef{
            .ratio = 8,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        },
        EcdsaInstanceDef.init(8),
    );
}

test "EcdsaInstanceDef: initDefault should return a default ECDSA instance def" {
    try expectEqual(
        EcdsaInstanceDef{
            .ratio = 512,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        },
        EcdsaInstanceDef.initDefault(),
    );
}

test "EcdsaInstanceDef: cellsPerBuiltin should return the number of cells per signature" {
    try expectEqual(
        CELLS_PER_SIGNATURE,
        EcdsaInstanceDef.initDefault().cellsPerBuiltin(),
    );
}

test "EcdsaInstanceDef: rangeCheckUnitsPerBuiltin should return 0" {
    try expectEqual(
        @as(u32, 0),
        EcdsaInstanceDef.initDefault().rangeCheckUnitsPerBuiltin(),
    );
}
