const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Represents the configuration for a diluted pool instance in Cairo.
pub const DilutedPoolInstanceDef = struct {
    const Self = @This();

    /// Logarithm of the ratio between diluted cells in the pool and CPU steps.
    ///
    /// Can be negative for scenarios with few builtins requiring diluted units (e.g., bitwise and Keccak).
    units_per_step: ?i32,

    /// Represents the spacing between consecutive information-carrying bits in diluted form.
    spacing: u32,

    /// Number of information bits (before dilution).
    n_bits: u32,

    /// Initializes a new `DilutedPoolInstanceDef` structure with default values.
    pub fn init() Self {
        return .{
            .units_per_step = 16,
            .spacing = 4,
            .n_bits = 16,
        };
    }

    /// Creates a `DilutedPoolInstanceDef` structure with custom values.
    ///
    /// # Arguments
    ///
    /// - `units_per_step`: Logarithm of the ratio between diluted cells in the pool and CPU steps.
    /// - `spacing`: Spacing between information-carrying bits in diluted form.
    /// - `n_bits`: Number of information bits before dilution.
    ///
    /// # Returns
    ///
    /// A `DilutedPoolInstanceDef` structure with specified custom values.
    pub fn from(units_per_step: i32, spacing: u32, n_bits: u32) Self {
        return .{
            .units_per_step = units_per_step,
            .spacing = spacing,
            .n_bits = n_bits,
        };
    }
};

test "DilutedPoolInstanceDef: init should initialize DilutedPoolInstanceDef properly" {
    try expectEqual(
        DilutedPoolInstanceDef{
            .units_per_step = 16,
            .spacing = 4,
            .n_bits = 16,
        },
        DilutedPoolInstanceDef.init(),
    );
}

test "DilutedPoolInstanceDef: from should initialize DilutedPoolInstanceDef properly using provided parameters" {
    try expectEqual(
        DilutedPoolInstanceDef{
            .units_per_step = 1,
            .spacing = 1,
            .n_bits = 1,
        },
        DilutedPoolInstanceDef.from(1, 1, 1),
    );
}
