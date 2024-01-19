const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Represents the configuration for a diluted pool instance in Cairo.
pub const DilutedPoolInstanceDef = struct {
    const Self = @This();

    /// Logarithm of the ratio between diluted cells in the pool and CPU steps.
    ///
    /// Can be negative for scenarios with few builtins requiring diluted units (e.g., bitwise and Keccak).
    units_per_step: ?i32 = 16,

    /// Represents the spacing between consecutive information-carrying bits in diluted form.
    spacing: u32 = 4,

    /// Number of information bits (before dilution).
    n_bits: u32 = 16,

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
    pub fn init(units_per_step: i32, spacing: u32, n_bits: u32) Self {
        return .{
            .units_per_step = units_per_step,
            .spacing = spacing,
            .n_bits = n_bits,
        };
    }
};

test "DilutedPoolInstanceDef: init should initialize DilutedPoolInstanceDef properly" {
    // Define the expected DilutedPoolInstanceDef with specified default values.
    const expected_instance = DilutedPoolInstanceDef{
        .units_per_step = 16,
        .spacing = 4,
        .n_bits = 16,
    };

    // Initialize a new DilutedPoolInstanceDef using the default initialization.
    const initialized_instance = DilutedPoolInstanceDef{};

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}

test "DilutedPoolInstanceDef: from should initialize DilutedPoolInstanceDef properly using provided parameters" {
    // Define the expected DilutedPoolInstanceDef with specified parameter values.
    const expected_instance = DilutedPoolInstanceDef{
        .units_per_step = 1,
        .spacing = 1,
        .n_bits = 1,
    };

    // Initialize a new DilutedPoolInstanceDef using the provided parameters.
    const initialized_instance = DilutedPoolInstanceDef.init(1, 1, 1);

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}
