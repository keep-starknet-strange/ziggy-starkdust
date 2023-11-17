const std = @import("std");
const Allocator = std.mem.Allocator;

const BitwiseBuiltinRunner = @import("./bitwise.zig").BitwiseBuiltinRunner;
const EcOpBuiltinRunner = @import("./ec_op.zig").EcOpBuiltinRunner;
const HashBuiltinRunner = @import("./hash.zig").HashBuiltinRunner;
const KeccakBuiltinRunner = @import("./keccak.zig").KeccakBuiltinRunner;
const OutputBuiltinRunner = @import("./output.zig").OutputBuiltinRunner;
const PoseidonBuiltinRunner = @import("./poseidon.zig").PoseidonBuiltinRunner;
const RangeCheckBuiltinRunner = @import("./range_check.zig").RangeCheckBuiltinRunner;
const SegmentArenaBuiltinRunner = @import("./segment_arena.zig").SegmentArenaBuiltinRunner;
const SignatureBuiltinRunner = @import("./signature.zig").SignatureBuiltinRunner;

const BitwiseBuiltinRunnerTmp = @import("../bitwise/bitwise.zig");

const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;

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
            .Bitwise => |*bitwise| bitwise.base,
            .EcOp => |*ec| ec.base,
            .Hash => |*hash| hash.base,
            .Output => |*output| output.base,
            .RangeCheck => |*range_check| range_check.base,
            .Keccak => |*keccak| keccak.base,
            .Signature => |*signature| signature.base,
            .Poseidon => |*poseidon| poseidon.base,
            .SegmentArena => |*segment_arena| @as(usize, @intCast(segment_arena.base.segment_index)),
        };
    }

    /// Deduces memory cell information for the built-in runner.
    ///
    /// This function deduces memory cell information for the specific type of built-in runner.
    ///
    /// # Arguments
    ///
    /// - `address`: The address of the memory cell.
    /// - `memory`: The memory manager for the current context.
    ///
    /// # Returns
    ///
    /// A `MaybeRelocatable` representing the deduced memory cell information, or an error if deduction fails.
    pub fn deduceMemoryCell(
        self: *const Self,
        allocator: Allocator,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        return switch (self.*) {
            // TODO: switch to `BitwiseBuiltinRunner` `deduceMemoryCell` function after migration of `deduce` to `BitwiseBuiltinRunner`
            .Bitwise => try BitwiseBuiltinRunnerTmp.deduce(address, memory),
            .EcOp => |ec| ec.deduceMemoryCell(address, memory),
            .Hash => |hash| hash.deduceMemoryCell(address, memory),
            .Output => |output| output.deduceMemoryCell(address, memory),
            .RangeCheck => |range_check| range_check.deduceMemoryCell(address, memory),
            .Keccak => |keccak| {
                var mut_keccak = keccak;
                return mut_keccak.deduceMemoryCell(allocator, address, memory);
            },
            .Signature => |signature| signature.deduceMemoryCell(address, memory),
            .Poseidon => |poseidon| poseidon.deduceMemoryCell(address, memory),
            .SegmentArena => |segment_arena| segment_arena.deduceMemoryCell(address, memory),
        };
    }
};
