const std = @import("std");

pub const CELLS_PER_HASH: u32 = 3;
pub const INPUT_CELLS_PER_HASH: u32 = 2;

pub const PedersenInstanceDef = struct {
    ratio: ?u32,
    _repetitions: u32,
    _element_height: u32,
    _element_bits: u32,
    _n_inputs: u32,
    _hash_limit: std.math.big.int.Managed,
};
