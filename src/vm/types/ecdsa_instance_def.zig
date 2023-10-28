/// Represents a ECDSA Instance Definition.
pub const EcdsaInstanceDef = struct {
    /// Ratio
    ratio: ?u32,
    /// Split to this many different components - for optimization.
    _repetitions: u32,
    /// Size of hash.
    _height: u32,
    /// Number of hash bits
    _n_hash_bits: u32,
};
