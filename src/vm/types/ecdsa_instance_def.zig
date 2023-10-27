pub const EcdsaInstanceDef = struct {
    const Self = @This();

    ratio: ?u32,
    _repetitions: u32,
    _height: u32,
    _n_hash_bits: u32,
};
