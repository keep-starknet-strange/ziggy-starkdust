const std = @import("std");
const Felt252 = @import("../fields/starknet.zig");

const ArrayList = std.ArrayList;

/// Stark ECDSA signature
pub const Signature = struct {
    const Self = @This();

    /// The `r` value of a signature
    r: ArrayList(Felt252),
    /// The `s` value of a signature
    s: ArrayList(Felt252),
};
