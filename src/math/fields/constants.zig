const Felt252 = @import("starknet.zig").Felt252;
const std = @import("std");

pub const STARKNET_PRIME = 0x800000000000011000000000000000000000000000000000000000000000001;
pub const FELT_BYTE_SIZE = 32;

pub const BASE = std.math.pow(u256, 2, 86);
