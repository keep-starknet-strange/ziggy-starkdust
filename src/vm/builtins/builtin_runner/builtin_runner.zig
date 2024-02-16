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
const KeccakInstanceDef = @import("../../types/keccak_instance_def.zig").KeccakInstanceDef;

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
            .SegmentArena => |*segment_arena| @intCast(segment_arena.base.segment_index),
            inline else => |*builtin| builtin.base,
        };
    }

    /// Retrieves the ratio associated with the built-in runner.
    ///
    /// For built-in runners other than SegmentArena and Output, this function returns the ratio
    /// specific to the type of built-in runner.
    ///
    /// For SegmentArena and Output built-in runners, `null` is returned, as they do not have an associated ratio.
    ///
    /// # Returns
    ///
    /// If applicable, the ratio associated with the built-in runner as a `u32`. If the built-in runner
    /// does not have an associated ratio, `null` is returned.
    pub fn ratio(self: *const BuiltinRunner) ?u32 {
        return switch (self.*) {
            .SegmentArena, .Output => null,
            inline else => |*builtin| builtin.ratio,
        };
    }

    /// Retrieves the number of cells per instance associated with the built-in runner.
    ///
    /// This function returns the number of memory cells per instance managed by the specific
    /// type of built-in runner. For built-in runners other than Output, it returns the value
    /// specific to the type of built-in runner. For Output built-in runners, it returns 0
    /// as Outputs do not have associated memory cells per instance.
    ///
    /// # Returns
    ///
    /// The number of cells per instance as a `u32`.
    pub fn cellsPerInstance(self: *const BuiltinRunner) u32 {
        return switch (self.*) {
            .Output => 0,
            inline else => |*builtin| builtin.cells_per_instance,
        };
    }

    /// Initializes a builtin with its required memory segments.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        switch (self.*) {
            inline else => |*builtin| try builtin.initSegments(segments),
        }
    }

    /// Derives necessary stack for a builtin.
    ///
    /// # Arguments
    ///
    ///  - `allocator`: The allocator to initialize the ArrayList.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        return switch (self.*) {
            inline else => |*builtin| try builtin.initialStack(allocator),
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
            .EcOp => |*ec| try ec.deduceMemoryCell(allocator, address, memory),
            .Keccak => |*keccak| try keccak.deduceMemoryCell(allocator, address, memory),
            .Poseidon => |*poseidon| try poseidon.deduceMemoryCell(allocator, address, memory),
            .Bitwise => |bitwise| try bitwise.deduceMemoryCell(address, memory),
            .Hash => |*hash| try hash.deduceMemoryCell(address, memory),
            inline else => |*builtin| builtin.deduceMemoryCell(address, memory),
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
            .Signature, .SegmentArena => .{ 0, 0 },
            inline else => |*builtin| builtin.getMemorySegmentAddresses(),
        };
    }

    /// Retrieves the number of used memory cells associated with the built-in runner.
    ///
    /// This function calculates and returns the total number of used memory cells managed by
    /// the specific type of built-in runner. It utilizes the provided `segments` to determine
    /// the used cells based on the memory segments allocated.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` managing memory segments.
    ///
    /// # Returns
    ///
    /// The total number of used memory cells as a `usize`, or an error if calculation fails.
    pub fn getUsedCells(self: *Self, segments: *MemorySegmentManager) !usize {
        return switch (self.*) {
            inline else => |*builtin| try builtin.getUsedCells(segments),
        };
    }

    /// Retrieves the number of used instances associated with the built-in runner.
    ///
    /// This function calculates and returns the total number of used instances managed by
    /// the specific type of built-in runner. It utilizes the provided `segments` to determine
    /// the used instances based on the memory segments allocated.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` managing memory segments.
    ///
    /// # Returns
    ///
    /// The total number of used instances as a `usize`, or an error if calculation fails.
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !usize {
        return switch (self.*) {
            .SegmentArena => 0,
            inline else => |*builtin| try builtin.getUsedInstances(segments),
        };
    }

    /// Retrieves the number of instances per component for the built-in runner.
    ///
    /// This function returns the number of instances per component for the specific type of
    /// built-in runner. Each built-in runner may have a different number of instances per
    /// component based on its configuration and purpose.
    ///
    /// # Returns
    ///
    /// A `usize` representing the number of instances per component for the built-in runner.
    pub fn getInstancesPerComponent(self: *Self) u32 {
        return switch (self.*) {
            .SegmentArena, .Output => 1,
            inline else => |*builtin| builtin.instances_per_component,
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

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .EcOp => |*ec_op| ec_op.deinit(),
            .Hash => |*hash| hash.deinit(),
            .Keccak => |*keccak| keccak.deinit(),
            else => {},
        }
    }
};

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

test "BuiltinRunner: ratio method" {
    // Initialize a BuiltinRunner for bitwise operations.
    const bitwise_builtin: BuiltinRunner = .{ .Bitwise = .{} };
    // Test the ratio method for bitwise_builtin.
    // We expect the ratio to be 256.
    try expectEqual(@as(?u32, 256), bitwise_builtin.ratio());

    // Initialize a BuiltinRunner for EC operations.
    var ec_op_builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };
    // Defer deinitialization of ec_op_builtin.
    defer ec_op_builtin.deinit();
    // Test the ratio method for ec_op_builtin.
    // We expect the ratio to be 256.
    try expectEqual(@as(?u32, 256), ec_op_builtin.ratio());

    // Initialize a BuiltinRunner for hash operations.
    var hash_builtin: BuiltinRunner = .{
        .Hash = HashBuiltinRunner.init(
            std.testing.allocator,
            100,
            true,
        ),
    };
    // Defer deinitialization of hash_builtin.
    defer hash_builtin.deinit();
    // Test the ratio method for hash_builtin.
    // We expect the ratio to be 100.
    try expectEqual(@as(?u32, 100), hash_builtin.ratio());

    // Initialize a BuiltinRunner for output operations.
    var output_builtin: BuiltinRunner = .{
        .Output = OutputBuiltinRunner.initDefault(std.testing.allocator),
    };
    defer output_builtin.deinit(); // Defer deinitialization of output_builtin.
    // Test the ratio method for output_builtin.
    // Since output operations do not have an associated ratio, we expect null.
    try expectEqual(null, output_builtin.ratio());

    // Initialize a BuiltinRunner for range check operations.
    const rangecheck_builtin: BuiltinRunner = .{ .RangeCheck = .{} };
    // Test the ratio method for rangecheck_builtin.
    // We expect the ratio to be 8.
    try expectEqual(@as(?u32, 8), rangecheck_builtin.ratio());

    // Initialize a Keccak instance definition.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);
    // Initialize a BuiltinRunner for Keccak operations.
    var keccak_builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };
    // Defer deinitialization of keccak_builtin.
    defer keccak_builtin.deinit();
    // Test the ratio method for keccak_builtin.
    // We expect the ratio to be 2048.
    try expectEqual(@as(?u32, 2048), keccak_builtin.ratio());
}

test "BuiltinRunner: cellsPerInstance method" {
    // Initialize a BuiltinRunner for bitwise operations.
    const bitwise_builtin: BuiltinRunner = .{ .Bitwise = .{} };
    // Test the cellsPerInstance method for bitwise_builtin.
    // We expect the number of cells per instance to be 256.
    try expectEqual(@as(u32, 5), bitwise_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for EC operations.
    var ec_op_builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };
    // Defer deinitialization of ec_op_builtin.
    defer ec_op_builtin.deinit();
    // Test the cellsPerInstance method for ec_op_builtin.
    // We expect the number of cells per instance to be 256.
    try expectEqual(@as(u32, 7), ec_op_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for hash operations.
    var hash_builtin: BuiltinRunner = .{
        .Hash = HashBuiltinRunner.init(
            std.testing.allocator,
            100,
            true,
        ),
    };
    // Defer deinitialization of hash_builtin.
    defer hash_builtin.deinit();
    // Test the cellsPerInstance method for hash_builtin.
    // We expect the number of cells per instance to be 100.
    try expectEqual(@as(?u32, 3), hash_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for output operations.
    var output_builtin: BuiltinRunner = .{
        .Output = OutputBuiltinRunner.initDefault(std.testing.allocator),
    };
    // Defer deinitialization of output_builtin.
    defer output_builtin.deinit();
    // Test the cellsPerInstance method for output_builtin.
    // Since output operations do not have associated cells per instance, we expect 0.
    try expectEqual(@as(u32, 0), output_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for range check operations.
    const rangecheck_builtin: BuiltinRunner = .{ .RangeCheck = .{} };
    // Test the cellsPerInstance method for rangecheck_builtin.
    // We expect the number of cells per instance to be 8.
    try expectEqual(@as(u32, 1), rangecheck_builtin.cellsPerInstance());

    // Initialize a Keccak instance definition.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);
    // Initialize a BuiltinRunner for Keccak operations.
    var keccak_builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };
    // Defer deinitialization of keccak_builtin.
    defer keccak_builtin.deinit();
    // Test the cellsPerInstance method for keccak_builtin.
    // We expect the number of cells per instance to be 2048.
    try expectEqual(@as(u32, 16), keccak_builtin.cellsPerInstance());
}
