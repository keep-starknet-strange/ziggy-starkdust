const BitwiseBuiltinRunner = @import("./bitwise.zig").BitwiseBuiltinRunner;
const EcOpBuiltinRunner = @import("./ec_op.zig").EcOpBuiltinRunner;
const HashBuiltinRunner = @import("./hash.zig").HashBuiltinRunner;
const KeccakBuiltinRunner = @import("./keccak.zig").KeccakBuiltinRunner;
const OutputBuiltinRunner = @import("./output.zig").OutputBuiltinRunner;
const PoseidonBuiltinRunner = @import("./poseidon.zig").PoseidonBuiltinRunner;
const RangeCheckBuiltinRunner = @import("./range_check.zig").RangeCheckBuiltinRunner;
const SegmentArenaBuiltinRunner = @import("./segment_arena.zig").SegmentArenaBuiltinRunner;
const SignatureBuiltinRunner = @import("./signature.zig").SignatureBuiltinRunner;

/// Built-in runner
pub const BuiltinRunner = union(enum) {
    const Self = @This();

    /// Bitwise built-in runner for bitwise operations.
    Bitwise: BitwiseBuiltinRunner,
    /// EC Operation built-in runner for elliptic curve operations.
    EcOp: EcOpBuiltinRunner,
    /// Hash built-in runner for hash operations.
    Hash: HashBuiltinRunner,
    /// Output built-in runner for output operations.
    Output: OutputBuiltinRunner,
    /// Range Check built-in runner for range check operations.
    RangeCheck: RangeCheckBuiltinRunner,
    /// Keccak built-in runner for Keccak operations.
    Keccak: KeccakBuiltinRunner,
    /// Signature built-in runner for signature operations.
    Signature: SignatureBuiltinRunner,
    /// Poseidon built-in runner for Poseidon operations.
    Poseidon: PoseidonBuiltinRunner,
    /// Segment Arena built-in runner for segment arena operations.
    SegmentArena: SegmentArenaBuiltinRunner,

    /// Get the base value of the built-in runner.
    ///
    /// This function returns the base value specific to the type of built-in runner.
    ///
    /// # Returns
    ///
    /// The base value as a `usize`.
    pub fn base(self: *const Self) usize {
        return switch (self.*) {
            .Bitwise => |*bitwise| bitwise.get_base(),
            .EcOp => |*ec| ec.get_base(),
            .Hash => |*hash| hash.get_base(),
            .Output => |*output| output.get_base(),
            .RangeCheck => |*range_check| range_check.get_base(),
            .Keccak => |*keccak| keccak.get_base(),
            .Signature => |*signature| signature.get_base(),
            .Poseidon => |*poseidon| poseidon.get_base(),
            .SegmentArena => |*segment_arena| segment_arena.get_base(),
        };
    }
};
