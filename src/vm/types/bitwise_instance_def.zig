/// Number of cells by bitwise operation
pub const CELLS_PER_BITWISE: u32 = 5;
/// Number of input cells by bitwise operation
pub const INPUT_CELLS_PER_BITWISE: u32 = 2;

pub const TOTAL_N_BITS_BITWISE_DEFAULT = 251;

/// Represents a Bitwise Instance Definition.
pub const BitwiseInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32 = 256,
    /// The number of bits in a single field element that are supported by the bitwise builtin.
    total_n_bits: u32 = TOTAL_N_BITS_BITWISE_DEFAULT,

    pub fn initDefault() Self {
        return .{ .ratio = 256, .total_n_bits = 251 };
    }

    pub fn from(ratio: ?u32) Self {
        return .{ .ratio = ratio, .total_n_bits = 251 };
    }
};
