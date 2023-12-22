/// Number of cells per Poseidon
pub const CELLS_PER_POSEIDON: u32 = 6;
/// Number of input cells per Poseidon
pub const INPUT_CELLS_PER_POSEIDON: u32 = 3;

/// Represents a Poseidon Instance Definition.
pub const PoseidonInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,

    pub fn init() Self {
        return .{ .ratio = 32 };
    }

    pub fn from(ratio: ?u32) Self {
        return .{ .ratio = ratio };
    }
};
