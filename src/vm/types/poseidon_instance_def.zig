/// Number of cells per Poseidon
pub const CELLS_PER_POSEIDON: u32 = 6;
/// Number of input cells per Poseidon
pub const INPUT_CELLS_PER_POSEIDON: u32 = 3;

/// Represents a Poseidon Instance Definition.
pub const PoseidonInstanceDef = struct {
    /// Ratio
    ratio: ?u32,
};
