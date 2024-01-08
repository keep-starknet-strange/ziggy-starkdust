const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Number of cells per Poseidon
pub const CELLS_PER_POSEIDON: u32 = 6;
/// Number of input cells per Poseidon
pub const INPUT_CELLS_PER_POSEIDON: u32 = 3;

/// Represents a Poseidon Instance Definition.
pub const PoseidonInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32 = 32,

    pub fn init(ratio: ?u32) Self {
        return .{ .ratio = ratio };
    }
};

test "PoseidonInstanceDef: test default implementation" {
    const poseiden_instance = PoseidonInstanceDef{};
    try expectEqual(poseiden_instance.ratio, 32);
}

test "PoseidonInstanceDef: test init implementation" {
    const poseiden_instance = PoseidonInstanceDef.init(64);
    try expectEqual(poseiden_instance.ratio, 64);
}
