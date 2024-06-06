const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Relocatable = @import("./memory/relocatable.zig").Relocatable;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;

/// An entry recorded representing the state of the VM at a given point in time.
pub const TraceEntry = struct {
    pc: Relocatable,
    ap: usize,
    fp: usize,
};

/// A trace entry for every instruction that was executed.
/// Holds the register values before the instruction was executed, after going through the relocation process.
pub const RelocatedTraceEntry = struct {
    ap: usize,
    fp: usize,
    pc: usize,
};

pub const RelocatedFelt252 = struct {
    v: [4]u64,

    const NONE_MASK: u64 = 1 << 63;
    pub const NONE: RelocatedFelt252 = .{ .v = .{
        0,
        0,
        0,
        RelocatedFelt252.NONE_MASK,
    } };

    pub fn init(f: Felt252) RelocatedFelt252 {
        return .{ .v = f.fe.limbs };
    }

    pub fn isNone(self: RelocatedFelt252) bool {
        return self.v[3] & RelocatedFelt252.NONE_MASK == RelocatedFelt252.NONE_MASK;
    }

    pub fn getValue(self: RelocatedFelt252) ?Felt252 {
        return if (self.isNone()) null else v: {
            break :v .{ .fe = .{ .limbs = self.v } };
        };
    }
};
