pub const CELLS_PER_EC_OP: u32 = 7;
pub const INPUT_CELLS_PER_EC_OP: u32 = 5;

pub const EcOpInstanceDef = struct {
    ratio: ?u32,
    scalar_height: u32,
    _scalar_bits: u32,
};
