const std = @import("std");

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
    hash_limit: u256,

    pub fn init() Self {
        return .{
            .ratio = 8,
            .repetitions = 4,
            .element_height = 256,
            .element_bits = 252,
            .n_inputs = 2,
            .hash_limit = PRIME,
        };
    }

    pub fn from(ratio: ?u32, repetitions: u32) Self {
        return .{
            .ratio = ratio,
            .repetitions = repetitions,
            .element_height = 256,
            .element_bits = 252,
            .n_inputs = 2,
            .hash_limit = PRIME,
        };
    }
};
