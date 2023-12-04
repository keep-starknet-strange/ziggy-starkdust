/// Number of cells per range check
pub const CELLS_PER_RANGE_CHECK: u32 = 1;

/// Represents a Range Check Instance Definition.
pub const RangeCheckInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Number of 16-bit range checks that will be used for each instance of the builtin.
    ///
    /// For example, n_parts=8 defines the range [0, 2^128).
    n_parts: u32,

    /// Number of units per builtin
    pub fn rangeCheckUnitsPerBuiltin(self: *Self) u32 {
        return self.n_parts;
    }

    pub fn default() Self {
        return .{
            .ratio = 8,
            .n_parts = 8,
        };
    }

    /// Creates a new instance of `RangeCheckInstanceDef` with the specified ratio and n_parts representation.
    ///
    /// # Parameters
    ///
    /// - `ratio`: An optional 32-bit integer representing the ratio for the Range check instance.
    /// - `n_pars`: An 32-bit integer representing number of parts.
    ///
    /// # Returns
    ///
    /// A new `RangeCheckInstanceDef` instance with the specified parameters.
    pub fn init(ratio: ?u32, n_parts: u32) Self {
        return .{
            .ratio = ratio,
            .n_parts = n_parts,
        };
    }
};
