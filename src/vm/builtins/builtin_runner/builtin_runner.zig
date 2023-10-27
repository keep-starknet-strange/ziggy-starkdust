const BitwiseBuiltinRunner = @import("./bitwise.zig").BitwiseBuiltinRunner;
const EcOpBuiltinRunner = @import("./ec_op.zig").EcOpBuiltinRunner;
const HashBuiltinRunner = @import("./hash.zig").HashBuiltinRunner;
const KeccakBuiltinRunner = @import("./keccak.zig").KeccakBuiltinRunner;
const OutputBuiltinRunner = @import("./output.zig").OutputBuiltinRunner;
const PoseidonBuiltinRunner = @import("./poseidon.zig").PoseidonBuiltinRunner;
const RangeCheckBuiltinRunner = @import("./range_check.zig").RangeCheckBuiltinRunner;
const SegmentArenaBuiltinRunner = @import("./segment_arena.zig").SegmentArenaBuiltinRunner;
const SignatureBuiltinRunner = @import("./signature.zig").SignatureBuiltinRunner;

pub const BuiltinRunner = union(enum) {
    const Self = @This();

    Bitwise: BitwiseBuiltinRunner,
    EcOp: EcOpBuiltinRunner,
    Hash: HashBuiltinRunner,
    Output: OutputBuiltinRunner,
    RangeCheck: RangeCheckBuiltinRunner,
    Keccak: KeccakBuiltinRunner,
    Signature: SignatureBuiltinRunner,
    Poseidon: PoseidonBuiltinRunner,
    SegmentArena: SegmentArenaBuiltinRunner,

    /// Returns the builtin's base
    pub fn base(self: *Self) usize {
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
