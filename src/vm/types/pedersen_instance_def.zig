const std = @import("std");

/// Each hash consists of 3 cells (two inputs and one output).
pub const CELLS_PER_HASH: u32 = 3;
/// Number of input cells per hash.
pub const INPUT_CELLS_PER_HASH: u32 = 2;

/// Represents a Pedersen Instance Definition.
pub const PedersenInstanceDef = struct {
    /// Ratio
    ratio: ?u32,
    /// Split to this many different components - for optimization.
    _repetitions: u32,
    /// Size of hash.
    _element_height: u32,
    /// Size of hash in bits.
    _element_bits: u32,
    /// Number of inputs for hash.
    _n_inputs: u32,
    /// The upper bound on the hash inputs.
    ///
    /// If None, the upper bound is 2^element_bits.
    _hash_limit: std.math.big.int.Managed,
};
