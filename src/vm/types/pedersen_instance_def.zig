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
    ratio: ?u32 = 8,
    /// Split to this many different components - for optimization.
    repetitions: u32 = 4,
    /// Size of hash.
    element_height: u32 = 256,
    /// Size of hash in bits.
    element_bits: u32 = 252,
    /// Number of inputs for hash.
    n_inputs: u32 = 2,
    /// The upper bound on the hash inputs.
    ///
    /// If None, the upper bound is 2^element_bits.
    hash_limit: u256 = PRIME,

    pub fn init(ratio: ?u32, repetitions: u32) Self {
        return .{
            .ratio = ratio,
            .repetitions = repetitions,
            .element_height = 256,
            .element_bits = 252,
            .n_inputs = 2,
            .hash_limit = PRIME,
        };
    }

    pub fn rangeCheckPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "PedersenInstanceDef: default implementation" {
    const builtin_instance = PedersenInstanceDef{
        .ratio = 8,
        .repetitions = 4,
        .element_height = 256,
        .element_bits = 252,
        .n_inputs = 2,
        .hash_limit = PRIME,
    };
    const default = PedersenInstanceDef{};
    try expectEqual(builtin_instance.ratio, default.ratio);
    try expectEqual(builtin_instance.repetitions, default.repetitions);
    try expectEqual(builtin_instance.element_height, default.element_height);
    try expectEqual(builtin_instance.element_bits, default.element_bits);
    try expectEqual(builtin_instance.n_inputs, default.n_inputs);
    try expectEqual(builtin_instance.hash_limit, default.hash_limit);
}

test "PedersenInstanceDef: init implementation" {
    const builtin_instance = PedersenInstanceDef{
        .ratio = 10,
        .repetitions = 2,
        .element_height = 256,
        .element_bits = 252,
        .n_inputs = 2,
        .hash_limit = PRIME,
    };
    const pederesen_init = PedersenInstanceDef.init(10, 2);
    try expectEqual(builtin_instance.ratio, pederesen_init.ratio);
    try expectEqual(builtin_instance.repetitions, pederesen_init.repetitions);
    try expectEqual(builtin_instance.element_height, pederesen_init.element_height);
    try expectEqual(builtin_instance.element_bits, pederesen_init.element_bits);
    try expectEqual(builtin_instance.n_inputs, pederesen_init.n_inputs);
    try expectEqual(builtin_instance.hash_limit, pederesen_init.hash_limit);
}

test "PedersenInstanceDef: rangeCheckPerBuiltin implementation" {
    const builtin_instance = PedersenInstanceDef{};
    try expectEqual(builtin_instance.rangeCheckPerBuiltin(), 0);
}
