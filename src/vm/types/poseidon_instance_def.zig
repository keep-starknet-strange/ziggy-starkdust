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

    /// Initializes a Poseidon Instance Definition with the specified ratio.
    ///
    /// # Parameters
    ///
    /// - `ratio`: The ratio to associate with the instance.
    ///
    /// # Returns
    ///
    /// A Poseidon Instance Definition with the specified ratio.
    pub fn init(ratio: ?u32) Self {
        return .{ .ratio = ratio };
    }
};

test "PoseidonInstanceDef: test default implementation" {
    // Initialize a PoseidonInstanceDef with default values.
    const poseidon_instance = PoseidonInstanceDef{};

    // Ensure that the default instance has the expected ratio.
    try expectEqual(@as(u32, 32), poseidon_instance.ratio);
}

test "PoseidonInstanceDef: test init implementation" {
    // Initialize a PoseidonInstanceDef using the init function with a specific ratio.
    const poseidon_instance = PoseidonInstanceDef.init(64);

    // Ensure that the initialized instance has the expected ratio.
    try expectEqual(@as(u32, 64), poseidon_instance.ratio);
}
