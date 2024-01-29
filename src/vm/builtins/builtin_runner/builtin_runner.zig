const std = @import("std");
const Allocator = std.mem.Allocator;
const Tuple = std.meta.Tuple;

const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;

const BitwiseBuiltinRunner = @import("./bitwise.zig").BitwiseBuiltinRunner;
const EcOpBuiltinRunner = @import("./ec_op.zig").EcOpBuiltinRunner;
const HashBuiltinRunner = @import("./hash.zig").HashBuiltinRunner;
const KeccakBuiltinRunner = @import("./keccak.zig").KeccakBuiltinRunner;
const OutputBuiltinRunner = @import("./output.zig").OutputBuiltinRunner;
const PoseidonBuiltinRunner = @import("./poseidon.zig").PoseidonBuiltinRunner;
const RangeCheckBuiltinRunner = @import("./range_check.zig").RangeCheckBuiltinRunner;
const SegmentArenaBuiltinRunner = @import("./segment_arena.zig").SegmentArenaBuiltinRunner;
const SignatureBuiltinRunner = @import("./signature.zig").SignatureBuiltinRunner;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const ArrayList = std.ArrayList;

/// The name of the output builtin.
pub const OUTPUT_BUILTIN_NAME = "output_builtin";

/// The name of the Pedersen hash builtin.
pub const HASH_BUILTIN_NAME = "pedersen_builtin";

/// The name of the range check builtin.
pub const RANGE_CHECK_BUILTIN_NAME = "range_check_builtin";

/// The name of the ECDSA signature verification builtin.
pub const SIGNATURE_BUILTIN_NAME = "ecdsa_builtin";

/// The name of the bitwise operations builtin.
pub const BITWISE_BUILTIN_NAME = "bitwise_builtin";

/// The name of the elliptic curve operations builtin.
pub const EC_OP_BUILTIN_NAME = "ec_op_builtin";

/// The name of the Keccak hash builtin.
pub const KECCAK_BUILTIN_NAME = "keccak_builtin";

/// The name of the Poseidon hash builtin.
pub const POSEIDON_BUILTIN_NAME = "poseidon_builtin";

/// The name of the segment arena builtin.
pub const SEGMENT_ARENA_BUILTIN_NAME = "segment_arena_builtin";

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

    /// Initializes a builtin with its required memory segments.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        switch (self.*) {
            .Bitwise => |*bitwise| try bitwise.initSegments(segments),
            .EcOp => |*ec| try ec.initSegments(segments),
            .Hash => |*hash| try hash.initSegments(segments),
            .Output => |*output| try output.initSegments(segments),
            .RangeCheck => |*range_check| try range_check.initSegments(segments),
            .Keccak => |*keccak| try keccak.initSegments(segments),
            .Signature => |*signature| try signature.initSegments(segments),
            .Poseidon => |*poseidon| try poseidon.initSegments(segments),
            .SegmentArena => |*segment_arena| try segment_arena.initSegments(segments),
        }
    }

    /// Derives necessary stack for a builtin.
    ///
    /// # Arguments
    ///
    ///  - `allocator`: The allocator to initialize the ArrayList.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        return switch (self.*) {
            .Bitwise => |*bitwise| try bitwise.initialStack(allocator),
            .EcOp => |*ec| try ec.initialStack(allocator),
            .Hash => |*hash| try hash.initialStack(allocator),
            .Output => |*output| try output.initialStack(allocator),
            .RangeCheck => |*range_check| try range_check.initialStack(allocator),
            .Keccak => |*keccak| try keccak.initialStack(allocator),
            .Signature => |*signature| try signature.initialStack(allocator),
            .Poseidon => |*poseidon| try poseidon.initialStack(allocator),
            .SegmentArena => |*segment_arena| try segment_arena.initialStack(allocator),
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
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        return switch (self.*) {
            .Bitwise => |bitwise| try bitwise.deduceMemoryCell(address, memory),
            .EcOp => |ec| ec.deduceMemoryCell(address, memory),
            .Hash => |*hash| try hash.deduceMemoryCell(address, memory),
            .Output => |output| output.deduceMemoryCell(address, memory),
            .RangeCheck => |range_check| range_check.deduceMemoryCell(address, memory),
            .Keccak => |*keccak| try keccak.deduceMemoryCell(allocator, address, memory),
            .Signature => |signature| signature.deduceMemoryCell(address, memory),
            .Poseidon => |*poseidon| try poseidon.deduceMemoryCell(allocator, address, memory),
            .SegmentArena => |segment_arena| segment_arena.deduceMemoryCell(address, memory),
        };
    }

    /// Retrieves the memory segment addresses associated with the built-in runner.
    ///
    /// This function returns a `Tuple` containing the starting address and optional stop address
    /// for each memory segment used by the specific type of built-in runner. The stop address may
    /// be `null` if the built-in runner doesn't have a distinct stop address for its memory segment.
    ///
    /// # Returns
    ///
    /// A `Tuple` containing the memory segment addresses as follows:
    /// - The starting address of the memory segment.
    /// - An optional stop address of the memory segment (may be `null`).
    pub fn getMemorySegmentAddresses(self: *Self) Tuple(&.{ usize, ?usize }) {
        // TODO: fill-in missing builtins when implemented
        return switch (self.*) {
            .Bitwise => |*bitwise| bitwise.getMemorySegmentAddresses(),
            .EcOp => .{ 0, 0 },
            .Hash => .{ 0, 0 },
            .Output => |*output| output.getMemorySegmentAddresses(),
            .RangeCheck => |*range_check| range_check.getMemorySegmentAddresses(),
            .Keccak => |*keccak| keccak.getMemorySegmentAddresses(),
            .Signature => .{ 0, 0 },
            .Poseidon => |*poseidon| poseidon.getMemorySegmentAddresses(),
            .SegmentArena => .{ 0, 0 },
        };
    }

    /// Gets the name of the built-in runner.
    ///
    /// This function returns the name associated with the specific type of built-in runner.
    ///
    /// # Returns
    ///
    /// A null-terminated byte slice representing the name of the built-in runner.
    pub fn name(self: *Self) []const u8 {
        return switch (self.*) {
            .Bitwise => BITWISE_BUILTIN_NAME,
            .EcOp => EC_OP_BUILTIN_NAME,
            .Hash => HASH_BUILTIN_NAME,
            .Output => OUTPUT_BUILTIN_NAME,
            .RangeCheck => RANGE_CHECK_BUILTIN_NAME,
            .Keccak => KECCAK_BUILTIN_NAME,
            .Signature => SIGNATURE_BUILTIN_NAME,
            .Poseidon => POSEIDON_BUILTIN_NAME,
            .SegmentArena => SEGMENT_ARENA_BUILTIN_NAME,
        };
    }

    /// Adds a validation rule to the built-in runner for memory validation.
    ///
    /// This method is used to add a validation rule specific to the type of built-in runner.
    /// For certain built-ins, like the Range Check built-in, additional memory validation rules may
    /// be necessary to ensure proper execution.
    ///
    /// # Arguments
    ///
    /// - `memory`: A pointer to the Memory manager for the current context.
    ///
    /// # Errors
    ///
    /// An error is returned if adding the validation rule fails.
    pub fn addValidationRule(self: *Self, memory: *Memory) !void {
        switch (self.*) {
            .RangeCheck => |*range_check| try range_check.addValidationRule(memory),
            else => {},
        }
    }
};
