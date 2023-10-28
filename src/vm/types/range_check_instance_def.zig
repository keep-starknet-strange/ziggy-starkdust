/// Number of cells per range check
pub const CELLS_PER_RANGE_CHECK: u32 = 1;

/// Represents a Range Check Instance Definition.
pub const RangeCheckInstanceDef = struct {
    /// Ratio
    ratio: ?u32,
    /// Number of 16-bit range checks that will be used for each instance of the builtin.
    ///
    /// For example, n_parts=8 defines the range [0, 2^128).
    n_parts: u32,
};
