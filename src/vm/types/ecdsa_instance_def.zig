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

    pub fn init() Self {
        return .{
            .ratio = 512,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
    }

    pub fn from(ratio: ?u32) Self {
        return .{
            .ratio = ratio,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
    }

    pub fn _cells_per_builtin(_: Self) u32 {
        return CELLS_PER_SIGNATURE;
    }

    pub fn _range_check_units_per_builtin(_: *const Self) u32 {
        return 0;
    }
};

test "EcdsaInstanceDef: test from" {
    const instance = EcdsaInstanceDef{
        .ratio = 8,
        .repetitions = 1,
        .height = 256,
        .n_hash_bits = 251,
    };
    try expectEqual(
        EcdsaInstanceDef.from(8),
        instance,
    );
}

test "EcdsaInstanceDef: test init" {
    const instance = EcdsaInstanceDef{
        .ratio = 512,
        .repetitions = 1,
        .height = 256,
        .n_hash_bits = 251,
    };
    try expectEqual(
        EcdsaInstanceDef.init(),
        instance,
    );
}

test "EcdsaInstanceDef: test cells_per_builtin" {
    const instance = EcdsaInstanceDef.init();
    try expectEqual(
        instance._cells_per_builtin(),
        CELLS_PER_SIGNATURE,
    );
}

test "EcdsaInstanceDef: test range_check_units_per_builtin" {
    const instance = EcdsaInstanceDef.init();
    try expectEqual(
        instance._range_check_units_per_builtin(),
        0,
    );
}
