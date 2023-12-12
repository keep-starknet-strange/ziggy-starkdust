/// Represents a ECDSA Instance Definition.
pub const EcdsaInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Split to this many different components - for optimization.
    repetitions: u32,
    /// Size of hash.
    height: u32,
    /// Number of hash bits
    n_hash_bits: u32,

    pub fn init() Self {
        return .{
            .ratio = 512,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
    }

    pub fn from(ratio: ?u32) Self {
        return .{
            .ratio = ratio,
            .repetitions = 1,
            .height = 256,
            .n_hash_bits = 251,
        };
    }
};
