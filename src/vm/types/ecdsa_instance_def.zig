const std = @import("std");
const expectEqual = std.testing.expectEqual;

pub const CELLS_PER_SIGNATURE: u32 = 2;
pub const _INPUTCELLS_PER_SIGNATURE: u32 = 2;

/// Represents a ECDSA Instance Definition.
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

    pub fn initDefault() Self {
        return .{
            .ratio = 512,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
    }

    pub fn init(ratio: ?u32) Self {
        return .{
            .ratio = ratio,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
    }

    pub fn cellsPerBuiltin(_: Self) u32 {
        return CELLS_PER_SIGNATURE;
    }

    pub fn rangeCheckUnitsPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "EcdsaInstanceDef: test init" {
    const instance = EcdsaInstanceDef{
        .ratio = 8,
        .repetitions = 1,
        .height = 256,
        .n_hash_bits = 251,
    };
    try expectEqual(
        EcdsaInstanceDef.init(8),
        instance,
    );
}

test "EcdsaInstanceDef: test initDefault" {
    const instance = EcdsaInstanceDef{
        .ratio = 512,
        .repetitions = 1,
        .height = 256,
        .n_hash_bits = 251,
    };
    try expectEqual(
        EcdsaInstanceDef.initDefault(),
        instance,
    );
}

test "EcdsaInstanceDef: test cellsPerBuiltin" {
    const instance = EcdsaInstanceDef.initDefault();
    try expectEqual(
        instance.cellsPerBuiltin(),
        CELLS_PER_SIGNATURE,
    );
}

test "EcdsaInstanceDef: test rangeCheckUnitsPerBuiltin" {
    const instance = EcdsaInstanceDef.initDefault();
    try expectEqual(
        instance.rangeCheckUnitsPerBuiltin(),
        0,
    );
}
