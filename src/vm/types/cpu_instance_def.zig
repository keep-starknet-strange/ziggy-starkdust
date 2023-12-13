const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// Represents the configuration for a CPU instance in Cairo.
pub const CpuInstanceDef = struct {
    const Self = @This();

    /// Ensures each 'call' instruction returns, even if the called function is malicious.
    safe_call: bool,

    /// Initializes a new `CpuInstanceDef` structure with default values.
    pub fn init() Self {
        return .{ .safe_call = true };
    }
};

test "CpuInstanceDef: init should initialize CpuInstanceDef properly" {
    try expectEqual(
        CpuInstanceDef{ .safe_call = true },
        CpuInstanceDef.init(),
    );
}
