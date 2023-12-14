const std = @import("std");
const OffsetValue = @import("../vm/types/programjson.zig").OffsetValue;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

/// Represents a hint reference structure used for hints in Zig.
///
/// This structure defines a hint reference containing two offset values, a dereference flag,
/// Ap tracking data, and Cairo type information.
pub const HintReference = struct {
    const Self = @This();
    /// First offset value within the hint reference.
    offset1: OffsetValue,
    /// Second offset value within the hint reference.
    offset2: ?OffsetValue,
    /// Flag indicating dereference within the hint reference.
    dereference: bool,
    /// Ap tracking data associated with the hint reference (optional, defaults to null).
    ap_tracking_data: ?ApTracking,
    /// Cairo type information related to the hint reference (optional, defaults to null).
    cairo_type: ?[]const u8,

    /// Initializes a hint reference with specified offsets and dereference flags.
    ///
    /// Params:
    ///   - `offset1`: First offset value.
    ///   - `offset2`: Second offset value.
    ///   - `inner_dereference`: Flag for inner dereference within the first offset value.
    ///   - `dereference`: Flag for dereference within the hint reference.
    pub fn init(
        offset1: i32,
        offset2: i32,
        inner_dereference: bool,
        dereference: bool,
    ) Self {
        return .{
            .offset1 = .{ .reference = .{ .FP, offset1, inner_dereference } },
            .offset2 = .{ .value = offset2 },
            .dereference = dereference,
            .ap_tracking_data = null,
            .cairo_type = null,
        };
    }

    /// Initializes a simple hint reference with the specified offset.
    ///
    /// Params:
    ///   - `offset1`: First offset value for the hint reference.
    pub fn init_simple(offset1: i32) Self {
        return .{
            .offset1 = .{ .reference = .{ .FP, offset1, false } },
            .offset2 = .{ .value = 0 },
            .dereference = true,
            .ap_tracking_data = null,
            .cairo_type = null,
        };
    }
};

test "HintReference: init should return a proper HintReference instance" {
    try expectEqual(
        HintReference{
            .offset1 = .{ .reference = .{ .FP, 10, true } },
            .offset2 = .{ .value = 22 },
            .dereference = false,
            .ap_tracking_data = null,
            .cairo_type = null,
        },
        HintReference.init(10, 22, true, false),
    );
}

test "HintReference: init_simple should return a proper HintReference instance" {
    try expectEqual(
        HintReference{
            .offset1 = .{ .reference = .{ .FP, 10, false } },
            .offset2 = .{ .value = 0 },
            .dereference = true,
            .ap_tracking_data = null,
            .cairo_type = null,
        },
        HintReference.init_simple(10),
    );
}
