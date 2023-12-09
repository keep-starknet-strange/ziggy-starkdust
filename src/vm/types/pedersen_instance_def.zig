const std = @import("std");

const ManagedBigInt = std.math.big.int.Managed;
const Limb = std.math.big.Limb;
const Allocator = std.mem.Allocator;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

/// Each hash consists of 3 cells (two inputs and one output).
pub const CELLS_PER_HASH: u32 = 3;
/// Number of input cells per hash.
pub const INPUT_CELLS_PER_HASH: u32 = 2;

/// Represents a Pedersen Instance Definition.
pub const PedersenInstanceDef = struct {
    const Self = @This();
    /// Ratio
    ratio: ?u32,
    /// Split to this many different components - for optimization.
    _repetitions: u32,
    /// Size of hash.
    _element_height: u32,
    /// Size of hash in bits.
    _element_bits: u32,
    /// Number of inputs for hash.
    _n_inputs: u32,
    /// The upper bound on the hash inputs.
    ///
    /// If None, the upper bound is 2^element_bits.
    _hash_limit: ManagedBigInt,
    /// The memory allocator. Can be needed for the deallocation of the VM resources.
    allocator: Allocator,

    pub fn default(allocator: Allocator) !Self {
        var limbs = try allocator.alloc(Limb, 8);
        limbs[0] = 1;
        limbs[1] = 0;
        limbs[2] = 0;
        limbs[3] = 0;
        limbs[4] = 0;
        limbs[5] = 0;
        limbs[6] = 17;
        limbs[7] = 134217728;

        return .{ .allocator = allocator, .ratio = 8, ._repetitions = 4, ._element_height = 256, ._element_bits = 252, ._n_inputs = 2, ._hash_limit = .{ .allocator = allocator, .limbs = limbs, .metadata = 1 } };
    }

    pub fn init(allocator: Allocator, ratio: ?u32, _repetitions: u32) !Self {
        var limbs = try allocator.alloc(Limb, 8);
        limbs[0] = 1;
        limbs[1] = 0;
        limbs[2] = 0;
        limbs[3] = 0;
        limbs[4] = 0;
        limbs[5] = 0;
        limbs[6] = 17;
        limbs[7] = 134217728;

        const hash_limits = ManagedBigInt{ .allocator = allocator, .limbs = limbs, .metadata = 1 };
        return .{ .ratio = ratio, ._repetitions = _repetitions, ._element_height = 256, ._element_bits = 252, ._n_inputs = 2, ._hash_limit = hash_limits, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self._hash_limit.deinit();
    }

    pub fn cellsPerBuiltin(_: *const Self) u32 {
        return CELLS_PER_HASH;
    }

    pub fn rangeCheckPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "PedersenInstanceDef: default implementation" {
    const allocator = std.testing.allocator;
    var limbs = [_]Limb{
        1,
        0,
        0,
        0,
        0,
        0,
        17,
        134217728,
    };
    const hash_limit = ManagedBigInt{ .allocator = allocator, .limbs = &limbs, .metadata = 1 };
    const builtin_instance = PedersenInstanceDef{ .ratio = 8, ._repetitions = 4, ._element_height = 256, ._element_bits = 252, ._n_inputs = 2, ._hash_limit = hash_limit, .allocator = allocator };
    var default = try PedersenInstanceDef.default(allocator);

    defer default.deinit();

    try expectEqual(builtin_instance.ratio, default.ratio);
    try expectEqual(builtin_instance._repetitions, default._repetitions);
    try expectEqual(builtin_instance._element_height, default._element_height);
    try expectEqual(builtin_instance._element_bits, default._element_bits);
    try expectEqual(builtin_instance._n_inputs, default._n_inputs);
    try expectEqual(builtin_instance._hash_limit.metadata, default._hash_limit.metadata);

    try expect(ManagedBigInt.eql(builtin_instance._hash_limit, default._hash_limit));
}

test "PedersenInstanceDef: init implementation" {
    const allocator = std.testing.allocator;
    var limbs = [_]Limb{
        1,
        0,
        0,
        0,
        0,
        0,
        17,
        134217728,
    };
    const hash_limits = ManagedBigInt{ .allocator = allocator, .limbs = &limbs, .metadata = 1 };
    const builtin_instance = PedersenInstanceDef{ .ratio = 10, ._repetitions = 2, ._element_height = 256, ._element_bits = 252, ._n_inputs = 2, ._hash_limit = hash_limits, .allocator = allocator };
    var pederesen_init = try PedersenInstanceDef.init(allocator, 10, 2);
    pederesen_init.deinit();

    try expectEqual(builtin_instance.ratio, pederesen_init.ratio);
    try expectEqual(builtin_instance._repetitions, pederesen_init._repetitions);
    try expectEqual(builtin_instance._element_height, pederesen_init._element_height);
    try expectEqual(builtin_instance._element_bits, pederesen_init._element_bits);
    try expectEqual(builtin_instance._n_inputs, pederesen_init._n_inputs);
    try expect(ManagedBigInt.eql(hash_limits, builtin_instance._hash_limit));
}

test "PedersenInstanceDef: cellsPerBuiltin implementation" {
    var builtin_instance = try PedersenInstanceDef.default(std.testing.allocator);
    defer builtin_instance.deinit();
    try expectEqual(builtin_instance.cellsPerBuiltin(), 3);
}

test "PedersenInstanceDef: rangeCheckPerBuiltin implementation" {
    var builtin_instance = try PedersenInstanceDef.default(std.testing.allocator);
    defer builtin_instance.deinit();
    try expectEqual(builtin_instance.rangeCheckPerBuiltin(), 0);
}
