const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const HintType = union(enum) {
    // TODO: Add missing types
    Felt252,
    u64,
};

pub const ExecutionScopes = struct {
    const Self = @This();
    data: ArrayList(std.StringHashMap(HintType)),

    pub fn enterScope(self: *Self, scope: std.StringHashMap(HintType)) void {
        self.data.append(scope);
    }

    pub fn exitScope(self: *Self) void {
        self.data.pop();
    }
};
