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
/// Hash limit
pub const PRIME: u256 = std.math.pow(u256, 2, 251) + 17 * std.math.pow(u256, 2, 192) + 1;

/// Represents a Pedersen Instance Definition.
pub const PedersenInstanceDef = struct {
    const Self = @This();
    /// Ratio
    ratio: ?u32 = 8,
    /// Split to this many different components - for optimization.
    repetitions: u32 = 4,
    /// Size of hash.
    element_height: u32 = 256,
    /// Size of hash in bits.
    element_bits: u32 = 252,
    /// Number of inputs for hash.
    n_inputs: u32 = 2,
    /// The upper bound on the hash inputs.
    ///
    /// If None, the upper bound is 2^element_bits.
    hash_limit: u256 = PRIME,

    /// Initializes a Pedersen Instance Definition with the specified ratio and repetitions.
    ///
    /// # Parameters
    ///
    /// - `ratio`: The ratio to associate with the instance.
    /// - `repetitions`: The number of components for optimization.
    ///
    /// # Returns
    ///
    /// A Pedersen Instance Definition with the specified ratio and repetitions.
    pub fn init(ratio: ?u32, repetitions: u32) Self {
        return .{ .ratio = ratio, .repetitions = repetitions };
    }

    /// Retrieves the number of cells per built-in Pedersen hash operation.
    ///
    /// # Parameters
    ///
    /// - `self`: Pointer to the Pedersen Instance Definition.
    ///
    /// # Returns
    ///
    /// The number of cells per built-in Pedersen hash operation.
    pub fn cellsPerBuiltin(_: *const Self) u32 {
        return CELLS_PER_HASH;
    }

    /// Retrieves the range check units per built-in Pedersen hash operation.
    ///
    /// # Parameters
    ///
    /// - `self`: Pointer to the Pedersen Instance Definition.
    ///
    /// # Returns
    ///
    /// The number of range check units per built-in Pedersen hash operation.
    pub fn rangeCheckPerBuiltin(_: *const Self) u32 {
        return 0;
    }
};

test "PedersenInstanceDef: default implementation" {
    // Define the expected PedersenInstanceDef with default values.
    const expected_instance = PedersenInstanceDef{
        .ratio = 8,
        .repetitions = 4,
        .element_height = 256,
        .element_bits = 252,
        .n_inputs = 2,
        .hash_limit = PRIME,
    };

    // Initialize a default PedersenInstanceDef.
    const default_instance = PedersenInstanceDef{};

    // Ensure that the default instance matches the expected instance.
    try expectEqual(expected_instance, default_instance);
}

test "PedersenInstanceDef: init implementation" {
    // Define the expected PedersenInstanceDef with specific values.
    const expected_instance = PedersenInstanceDef{
        .ratio = 10,
        .repetitions = 2,
        .element_height = 256,
        .element_bits = 252,
        .n_inputs = 2,
        .hash_limit = PRIME,
    };

    // Initialize a new PedersenInstanceDef using the init function with specific values.
    const initialized_instance = PedersenInstanceDef.init(10, 2);

    // Ensure that the initialized instance matches the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}

test "PedersenInstanceDef: cellsPerBuiltin should return the number of cells per hash" {
    // Initialize a default PedersenInstanceDef.
    const builtin_instance = PedersenInstanceDef{};

    // Call the cellsPerBuiltin method and ensure it returns the expected number of cells.
    try expectEqual(
        @as(u32, 3),
        builtin_instance.cellsPerBuiltin(),
    );
}

test "PedersenInstanceDef: rangeCheckPerBuiltin should return zero" {
    // Initialize a default PedersenInstanceDef.
    const builtin_instance = PedersenInstanceDef{};

    // Call the rangeCheckPerBuiltin method and ensure it returns zero.
    try expectEqual(
        @as(u32, 0),
        builtin_instance.rangeCheckPerBuiltin(),
    );
}
