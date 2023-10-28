const std = @import("std");

const ArrayList = std.ArrayList;

/// Represents a Keccak Instance Definition.
pub const KeccakInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// The input and output are 1600 bits that are represented using a sequence of field elements in the following pattern.
    ///
    /// For example [64] * 25 means 25 field elements each containing 64 bits.
    _state_rep: ArrayList(u32),
    /// Should equal n_diluted_bits.
    _instance_per_component: u32,

    /// Number of cells per built in
    pub fn cells_per_builtin(self: *Self) u32 {
        return 2 * @as(u32, self._state_rep.items.len);
    }
};
