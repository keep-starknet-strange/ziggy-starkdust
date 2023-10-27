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
    Bitwise: BitwiseBuiltinRunner,
    EcOp: EcOpBuiltinRunner,
    Hash: HashBuiltinRunner,
    Output: OutputBuiltinRunner,
    RangeCheck: RangeCheckBuiltinRunner,
    Keccak: KeccakBuiltinRunner,
    Signature: SignatureBuiltinRunner,
    Poseidon: PoseidonBuiltinRunner,
    SegmentArena: SegmentArenaBuiltinRunner,
};
