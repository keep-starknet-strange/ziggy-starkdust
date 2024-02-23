const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const HintError = @import("../error.zig").HintError;

pub const HintType = union(enum) {
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

    pub fn enterScope(self: *Self, scope: std.StringHashMap(HintType)) !void {
        try self.data.append(scope);
    }

    pub fn exitScope(self: *Self) !void {
        if (self.data.items.len == 0) return HintError.FromScopeError;
        var last = self.data.pop();
        last.deinit();
    }

    ///Returns the value in the current execution scope that matches the name and is of the given generic type
    pub fn get(self: *const Self, name: []const u8) !HintType {
        return (self.getLocalVariableMut() orelse return HintError.VariableNotInScopeError).get(name) orelse HintError.VariableNotInScopeError;
    }

    pub fn getFelt(self: *const Self, name: []const u8) !Felt252 {
        return switch (try self.get(name)) {
            .felt => |f| f,
            else => HintError.VariableNotInScopeError,
        };
    }

    ///Returns a dictionary containing the variables present in the current scope
    pub fn getLocalVariableMut(self: *const Self) ?*std.StringHashMap(HintType) {
        if (self.data.items.len > 0) return &self.data.items[self.data.items.len - 1];
        return null;
    }

    ///Creates or updates an existing variable given its name and boxed value
    pub fn assignOrUpdateVariable(self: *Self, var_name: []const u8, var_value: HintType) !void {
        var m = self.getLocalVariableMut() orelse return;
        try m.put(var_name, var_value);
    }
};
