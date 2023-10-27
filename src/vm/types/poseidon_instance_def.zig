pub const CELLS_PER_POSEIDON: u32 = 6;
pub const INPUT_CELLS_PER_POSEIDON: u32 = 3;

pub const PoseidonInstanceDef = struct {
    const Self = @This();

    ratio: ?u32,
};
