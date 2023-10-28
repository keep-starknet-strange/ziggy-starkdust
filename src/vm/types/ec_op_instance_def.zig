/// Each EC operation P + m * Q = R contains 7 cells:
/// P_x, P_y, Q_x, Q_y, m, R_x, R_y.
pub const CELLS_PER_EC_OP: u32 = 7;
/// Number of input cells per EC operation
pub const INPUT_CELLS_PER_EC_OP: u32 = 5;

/// Represents a EC Operation Instance Definition.
pub const EcOpInstanceDef = struct {
    /// Ratio
    ratio: ?u32,
    /// Size of coefficient.
    scalar_height: u32,
    /// Scalar bits
    _scalar_bits: u32,
};
