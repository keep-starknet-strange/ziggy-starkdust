const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;

const HintType = union(enum) {
    // TODO: Add missing types
    felt: Felt252,
    u64: u64,
};

pub const ExecutionScopes = struct {
    const Self = @This();
    data: ArrayList(std.StringHashMap(HintType)),

    pub fn init(allocator: Allocator) !Self {
        var d = ArrayList(std.StringHashMap(HintType)).init(allocator);
        errdefer d.deinit();

        try d.append(std.StringHashMap(HintType).init(allocator));

        return .{
            .data = d,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.data.items) |*it| {
            it.deinit();
        }
        self.data.deinit();
    }

    pub fn enterScope(self: *Self, scope: std.StringHashMap(HintType)) void {
        self.data.append(scope);
    }

    pub fn exitScope(self: *Self) void {
        self.data.pop();
    }

    ///Returns a dictionary containing the variables present in the current scope
    pub fn getLocalVariableMut(self: *const Self) ?*std.StringHashMap(HintType) {
        if (self.data.items.len > 0) return &self.data.items[self.data.items.len - 1];

        return null;
    }

    ///Creates or updates an existing variable given its name and boxed value
    pub fn assignOrUpdateVariable(self: *Self, var_name: []const u8, var_value: HintType) !void {
        if (self.getLocalVariableMut()) |local_variables| try local_variables.put(var_name, var_value);
    }
};
