const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Represents a Keccak Instance Definition.
pub const KeccakInstanceDef = struct {
    const Self = @This();

    /// Ratio associated with the instance.
    ratio: ?u32 = 2048,
    /// The input and output are 1600 bits that are represented using a sequence of field elements.
    ///
    /// For example, [64] * 25 means 25 field elements, each containing 64 bits.
    state_rep: ArrayList(u32),
    /// Should equal n_diluted_bits.
    instance_per_component: u32 = 16,

    /// Initializes a default instance of `KeccakInstanceDef` with an allocator.
    ///
    /// This function initializes a default `KeccakInstanceDef` instance with the `ratio` set to 2048
    /// and default state representation and instance per component values.
    ///
    /// # Parameters
    ///
    /// - `allocator`: The allocator for memory allocation.
    ///
    /// # Returns
    ///
    /// A new `KeccakInstanceDef` instance initialized with default values.
    pub fn initDefault(allocator: Allocator) !Self {
        var instance_per_component = ArrayList(u32).init(allocator);
        errdefer instance_per_component.deinit();
        try instance_per_component.appendNTimes(200, 8);
        return .{ .state_rep = instance_per_component };
    }

    /// Creates a new instance of `KeccakInstanceDef` with the specified ratio and state representation.
    ///
    /// This function initializes a new `KeccakInstanceDef` instance with the provided `ratio` and
    /// `state_rep` values, and sets the `instance_per_component` to a default value of 16.
    ///
    /// # Parameters
    ///
    /// - `ratio`: An optional 32-bit integer representing the ratio for the Keccak instance.
    /// - `state_rep`: An `ArrayList` of 32-bit integers specifying the state representation pattern, state_rep owner become this struct
    ///
    /// # Returns
    ///
    /// A new `KeccakInstanceDef` instance with the specified parameters.
    pub fn init(ratio: ?u32, state_rep: ArrayList(u32)) Self {
        return .{
            .ratio = ratio,
            .state_rep = state_rep,
        };
    }

    /// Retrieves the number of cells per built-in Keccak operation.
    ///
    /// # Returns
    ///
    /// The number of cells per built-in Keccak operation based on the state representation length.
    pub fn cellsPerBuiltin(self: *const Self) u32 {
        return 2 * @as(
            u32,
            @intCast(self.state_rep.items.len),
        );
    }

    /// Retrieves the number of range check units per built-in Keccak operation.
    ///
    /// # Returns
    ///
    /// The number of range check units per built-in Keccak operation.
    pub fn rangeCheckUnitsPerBuiltin(_: *const Self) u32 {
        return 0;
    }

    /// Frees the resources owned by this instance of `KeccakInstanceDef`.
    ///
    /// This function deallocates memory associated with the state representation.
    pub fn deinit(self: *Self) void {
        self.state_rep.deinit();
    }
};

test "KeccakInstanceDef: initDefault should init a Keccak instance def with default values" {
    // Initializing an ArrayList for instance_per_component.
    var instance_per_component = ArrayList(u32).init(std.testing.allocator);
    defer instance_per_component.deinit();
    try instance_per_component.appendNTimes(200, 8);

    // Initializing a Keccak instance def using `initDefault`.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);
    defer keccak_instance_def.deinit();

    // Verifying equality of `ratio` in the instance with an expected value.
    try expectEqual(
        @as(?u32, 2048),
        keccak_instance_def.ratio,
    );
    // Verifying equality of `instance_per_component` in the instance with an expected value.
    try expectEqual(
        @as(u32, 16),
        keccak_instance_def.instance_per_component,
    );
    // Verifying equality of `state_rep` items in the instance with `instance_per_component`.
    try expectEqualSlices(
        u32,
        instance_per_component.items,
        keccak_instance_def.state_rep.items,
    );
}

test "KeccakInstanceDef: init should init a Keccak instance def with provided ratio and state rep" {
    // Initializing an ArrayList for state_rep.
    var state_rep = ArrayList(u32).init(std.testing.allocator);
    defer state_rep.deinit();
    try state_rep.appendNTimes(50, 8);

    // Creating a Keccak instance def using `init` with specified ratio and state representation.
    const keccak_instance_def = KeccakInstanceDef.init(122, state_rep);

    // Verifying equality of `ratio` in the instance with the provided ratio value.
    try expectEqual(
        @as(?u32, 122),
        keccak_instance_def.ratio,
    );
    // Verifying equality of `instance_per_component` in the instance with an expected value.
    try expectEqual(
        @as(u32, 16),
        keccak_instance_def.instance_per_component,
    );
    // Verifying equality of `state_rep` items in the instance with the provided state_rep.
    try expectEqualSlices(
        u32,
        state_rep.items,
        keccak_instance_def.state_rep.items,
    );
}

test "KeccakInstanceDef: cellsPerBuiltin function should return CELLS_PER_EC_OP" {
    // Initializing a Keccak instance def using `initDefault`.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);
    defer keccak_instance_def.deinit();

    // Verifying that `cellsPerBuiltin` returns the expected value.
    try expectEqual(
        @as(u32, 16),
        keccak_instance_def.cellsPerBuiltin(),
    );
}

test "KeccakInstanceDef: rangeCheckUnitsPerBuiltin function should return 0" {
    // Initializing a Keccak instance def using `initDefault`.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);

    defer keccak_instance_def.deinit();

    // Verifying that `rangeCheckUnitsPerBuiltin` returns the expected value.
    try expectEqual(
        @as(u32, 0),
        keccak_instance_def.rangeCheckUnitsPerBuiltin(),
    );
}
