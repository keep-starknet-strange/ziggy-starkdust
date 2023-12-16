const std = @import("std");

const ManagedBigInt = std.math.big.int.Managed;
const Limb = std.math.big.Limb;
const Allocator = std.mem.Allocator;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

/// Each hash consists of 3 cells (two inputs and one output).
pub const CELLS_PER_HASH: u32 = 3;
/// Number of input cells per hash.
pub const INPUT_CELLS_PER_HASH: u32 = 2;
/// Hash limit
pub const PRIME: u256 = std.math.pow(u256, 2, 251) + 17 * std.math.pow(u256, 2, 192) + 1;

/// Represents a Pedersen Instance Definition.
pub const PedersenInstanceDef = struct {
    const Self = @This();
    /// Ratio
    ratio: ?u32,
    /// Split to this many different components - for optimization.
    repetitions: u32,
    /// Size of hash.
    element_height: u32,
    /// Size of hash in bits.
    element_bits: u32,
    /// Number of inputs for hash.
    n_inputs: u32,
    /// The upper bound on the hash inputs.
    ///
    /// If None, the upper bound is 2^element_bits.
    _hash_limit: u256,

    pub fn initDefault() !Self {
        return .{
            .ratio = 8,
            ._repetitions = 4,
            ._element_height = 256,
            ._element_bits = 252,
            ._n_inputs = 2,
            ._hash_limit = PRIME,
        };
    }

    pub fn init(ratio: ?u32, _repetitions: u32) !Self {
        return .{
            .ratio = ratio,
            ._repetitions = _repetitions,
            ._element_height = 256,
            ._element_bits = 252,
            ._n_inputs = 2,
            ._hash_limit = PRIME,
        };
    }

    pub fn cellsPerBuiltin(_: *const Self) u32 {
        return CELLS_PER_HASH;
    }

    pub fn rangeCheckPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "PedersenInstanceDef: default implementation" {
    const builtin_instance = PedersenInstanceDef{
        .ratio = 8,
        ._repetitions = 4,
        ._element_height = 256,
        ._element_bits = 252,
        ._n_inputs = 2,
        ._hash_limit = PRIME,
    };
    var default = try PedersenInstanceDef.initDefault();
    try expectEqual(builtin_instance.ratio, default.ratio);
    try expectEqual(builtin_instance._repetitions, default._repetitions);
    try expectEqual(builtin_instance._element_height, default._element_height);
    try expectEqual(builtin_instance._element_bits, default._element_bits);
    try expectEqual(builtin_instance._n_inputs, default._n_inputs);
    try expectEqual(builtin_instance._hash_limit, default._hash_limit);
}

test "PedersenInstanceDef: init implementation" {
    const builtin_instance = PedersenInstanceDef{
        .ratio = 10,
        ._repetitions = 2,
        ._element_height = 256,
        ._element_bits = 252,
        ._n_inputs = 2,
        ._hash_limit = PRIME,
    };
    var pederesen_init = try PedersenInstanceDef.init(10, 2);
    try expectEqual(builtin_instance.ratio, pederesen_init.ratio);
    try expectEqual(builtin_instance._repetitions, pederesen_init._repetitions);
    try expectEqual(builtin_instance._element_height, pederesen_init._element_height);
    try expectEqual(builtin_instance._element_bits, pederesen_init._element_bits);
    try expectEqual(builtin_instance._n_inputs, pederesen_init._n_inputs);
    try expectEqual(builtin_instance._hash_limit, pederesen_init._hash_limit);
}

test "PedersenInstanceDef: cellsPerBuiltin implementation" {
    var builtin_instance = try PedersenInstanceDef.initDefault();
    try expectEqual(builtin_instance.cellsPerBuiltin(), 3);
}

test "PedersenInstanceDef: rangeCheckPerBuiltin implementation" {
    var builtin_instance = try PedersenInstanceDef.initDefault();
    try expectEqual(builtin_instance.rangeCheckPerBuiltin(), 0);
}
