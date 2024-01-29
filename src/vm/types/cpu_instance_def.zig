const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Represents the configuration for a CPU instance in Cairo.
pub const CpuInstanceDef = struct {
    const Self = @This();

    /// Ensures each 'call' instruction returns, even if the called function is malicious.
    safe_call: bool = true,
};

test "CpuInstanceDef: default initialization should be correct with `safe_call` set to true" {
    // Define the expected CpuInstanceDef with `safe_call` set to true.
    const expected_instance = CpuInstanceDef{ .safe_call = true };

    // Initialize a new CpuInstanceDef with the default initialization.
    const initialized_instance = CpuInstanceDef{};

    // Ensure that the initialized instance is equal to the expected instance.
    try expectEqual(expected_instance, initialized_instance);
}
