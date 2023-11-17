const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// Represents a Keccak Instance Definition.
pub const KeccakInstanceDef = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// The input and output are 1600 bits that are represented using a sequence of field elements in the following pattern.
    ///
    /// For example [64] * 25 means 25 field elements each containing 64 bits.
    _state_rep: ArrayList(u32),
    /// Should equal n_diluted_bits.
    _instance_per_component: u32,

    pub fn default(allocator: Allocator) !Self {
        var instance_per_component = ArrayList(u32).init(allocator);
        try instance_per_component.appendNTimes(200, 8);
        return .{
            // ratio should be equal to 2 ** 11 -> 2048
            .ratio = 2048,
            ._state_rep = instance_per_component,
            ._instance_per_component = 16,
        };
    }

    /// Creates a new instance of `KeccakInstanceDef` with the specified ratio and state representation.
    ///
    /// This function initializes a new `KeccakInstanceDef` instance with the provided `ratio` and
    /// `_state_rep` values, and sets the `_instance_per_component` to a default value of 16.
    ///
    /// # Parameters
    ///
    /// - `ratio`: An optional 32-bit integer representing the ratio for the Keccak instance.
    /// - `_state_rep`: An `ArrayList` of 32-bit integers specifying the state representation pattern.
    ///
    /// # Returns
    ///
    /// A new `KeccakInstanceDef` instance with the specified parameters.
    pub fn new(ratio: ?u32, _state_rep: ArrayList(u32)) Self {
        return .{
            .ratio = ratio,
            ._state_rep = _state_rep,
            ._instance_per_component = 16,
        };
    }

    /// Number of cells per built in
    pub fn cells_per_builtin(self: *const Self) u32 {
        return 2 * @as(
            u32,
            @intCast(self._state_rep.items.len),
        );
    }

    /// Frees the resources owned by this instance of `KeccakInstanceDef`.
    pub fn deinit(self: *Self) void {
        self._state_rep.deinit();
    }
};
