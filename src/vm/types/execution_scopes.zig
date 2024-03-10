const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const HintError = @import("../error.zig").HintError;
const ExecScopeError = @import("../error.zig").ExecScopeError;

/// Represents the possible types of variables in the hint scope.
pub const HintType = union(enum) {
    const Self = @This();
    // TODO: Add missing types
    felt: Felt252,
    u64: u64,
    u64_list: ArrayList(u64),
    felt_map_of_u64_list: std.AutoHashMap(Felt252, std.ArrayList(u64)),

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .felt_map_of_u64_list => |*d| {
                var it = d.valueIterator();
                while (it.next()) |v| v.deinit();

                d.deinit();
            },
            .u64_list => |d| {
                d.deinit();
            },
            else => {},
        }
    }
};

/// Represents the execution scope with variables.
pub const ExecutionScopes = struct {
    const Self = @This();
    data: ArrayList(std.StringHashMap(HintType)),

    /// Initializes the execution scope.
    pub fn init(allocator: Allocator) !Self {
        var d = ArrayList(std.StringHashMap(HintType)).init(allocator);
        errdefer d.deinit();

        try d.append(std.StringHashMap(HintType).init(allocator));

        return .{ .data = d };
    }

    /// Deinitializes the execution scope.
    pub fn deinit(self: *Self) void {
        for (self.data.items) |*m| {
            var it = m.valueIterator();

            while (it.next()) |h| h.deinit();

            m.deinit();
        }
        self.data.deinit();
    }

    /// Enters a new scope in the execution scope.
    pub fn enterScope(self: *Self, scope: std.StringHashMap(HintType)) !void {
        try self.data.append(scope);
    }

    /// Exits the current scope in the execution scope.
    pub fn exitScope(self: *Self) !void {
        if (self.data.items.len == 1) return ExecScopeError.ExitMainScopeError;
        var last = self.data.pop();
        last.deinit();
    }

    /// Returns the value in the current execution scope that matches the name and is of the given generic type.
    pub fn get(self: *const Self, name: []const u8) !HintType {
        return (self.getLocalVariable() orelse
            return HintError.VariableNotInScopeError).get(name) orelse
            HintError.VariableNotInScopeError;
    }

    /// Returns a reference to the value in the current execution scope that matches the name and is of the given generic type.
    pub fn getRef(self: *const Self, name: []const u8) !*HintType {
        return (self.getLocalVariable() orelse
            return HintError.VariableNotInScopeError).getPtr(name) orelse
            HintError.VariableNotInScopeError;
    }

    /// Returns the value in the current execution scope that matches the name and is of the given type.
    pub fn getFelt(self: *const Self, name: []const u8) !Felt252 {
        return switch (try self.get(name)) {
            .felt => |f| f,
            // in keccak implemntation of rust, they downcast u64 to felt
            .u64 => |v| Felt252.fromInt(u64, v),
            else => HintError.VariableNotInScopeError,
        };
    }

    /// Returns the value in the current execution scope that matches the name and is of the given type.
    pub fn getValue(
        self: *const Self,
        comptime T: @typeInfo(HintType).Union.tag_type.?,
        name: []const u8,
    ) !@typeInfo(HintType).Union.fields[@intFromEnum(T)].type {
        return switch (T) {
            .felt => switch (try self.get(name)) {
                .felt => |f| f,
                else => HintError.VariableNotInScopeError,
            },
            .u64 => switch (try self.get(name)) {
                .u64 => |v| v,
                else => HintError.VariableNotInScopeError,
            },
            .u64_list => switch (try self.get(name)) {
                .u64_list => |list| try list.clone(),
                else => HintError.VariableNotInScopeError,
            },
            .felt_map_of_u64_list => switch (try self.get(name)) {
                .felt_map_of_u64_list => |v| v,
                else => HintError.VariableNotInScopeError,
            },
        };
    }

    /// Returns a reference to the value in the current execution scope that matches the name and is of the given type.
    pub fn getValueRef(
        self: *const Self,
        comptime T: @typeInfo(HintType).Union.tag_type.?,
        name: []const u8,
    ) !*@typeInfo(HintType).Union.fields[@intFromEnum(T)].type {
        const r = try self.getRef(name);
        return switch (T) {
            .felt => switch (r.*) {
                .felt => &r.felt,
                else => HintError.VariableNotInScopeError,
            },
            .u64 => switch (r.*) {
                .u64 => &r.u64,
                else => HintError.VariableNotInScopeError,
            },
            .u64_list => switch (r.*) {
                .u64_list => &r.u64_list,
                else => HintError.VariableNotInScopeError,
            },
            .felt_map_of_u64_list => switch (r.*) {
                .felt_map_of_u64_list => &r.felt_map_of_u64_list,
                else => HintError.VariableNotInScopeError,
            },
        };
    }

    /// Returns a dictionary containing the variables present in the current scope.
    pub fn getLocalVariable(self: *const Self) ?*const std.StringHashMap(HintType) {
        return if (self.data.items.len > 0)
            &self.data.items[self.data.items.len - 1]
        else
            null;
    }

    /// Returns a mutable dictionary containing the variables present in the current scope.
    pub fn getLocalVariableMut(self: *const Self) ?*std.StringHashMap(HintType) {
        return if (self.data.items.len > 0)
            &self.data.items[self.data.items.len - 1]
        else
            null;
    }

    /// Creates or updates an existing variable given its name and boxed value.
    pub fn assignOrUpdateVariable(self: *Self, var_name: []const u8, var_value: HintType) !void {
        var m = self.getLocalVariableMut() orelse return;
        try m.put(var_name, var_value);
    }

    /// Removes a variable from the current scope given its name.
    pub fn deleteVariable(self: *Self, var_name: []const u8) void {
        if (self.getLocalVariableMut()) |*v| _ = v.*.remove(var_name);
    }
};

test "ExecutionScopes: initialize execution scopes" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();
    // Expect the length of the data items to be 1.
    try expectEqual(@as(usize, 1), scopes.data.items.len);
}

test "ExecutionScopes: get local variables" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();
    // Initialize a new scope.
    var scope = std.StringHashMap(HintType).init(std.testing.allocator);
    // Put a variable "a" with value 2 into the scope.
    try scope.put("a", .{ .felt = Felt252.fromInt(u8, 2) });
    // Append the scope to execution scopes.
    try scopes.data.append(scope);
    // Expect the count of local variables to be 1.
    try expectEqual(@as(usize, 1), scopes.getLocalVariable().?.count());
    // Expect the value of variable "a" to be 2.
    try expectEqual(
        HintType{ .felt = Felt252.fromInt(u8, 2) },
        scopes.getLocalVariableMut().?.get("a"),
    );
}

test "ExecutionScopes: enter new scope" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Initialize a new scope with variable "a" having value 2.
    var new_scope = std.StringHashMap(HintType).init(std.testing.allocator);
    try new_scope.put("a", .{ .felt = Felt252.fromInt(u8, 2) });

    // Initialize another scope with variable "b" having value 1.
    var scope = std.StringHashMap(HintType).init(std.testing.allocator);
    try scope.put("b", .{ .felt = Felt252.fromInt(u8, 1) });

    // Append the second scope to execution scopes.
    try scopes.data.append(scope);

    // Expect the count of local variables to be 1.
    try expectEqual(@as(usize, 1), scopes.getLocalVariable().?.count());
    // Expect the value of variable "b" in the current scope to be 1.
    try expectEqual(
        HintType{ .felt = Felt252.fromInt(u8, 1) },
        scopes.getLocalVariable().?.get("b"),
    );

    // Enter the new scope into execution scopes.
    try scopes.enterScope(new_scope);

    // Check that variable `b` cannot be accessed in the new scope.
    try expectEqual(
        null,
        scopes.getLocalVariable().?.get("b"),
    );
    // Expect the count of local variables to be 1 in the new scope.
    try expectEqual(@as(usize, 1), scopes.getLocalVariable().?.count());
    // Expect the value of variable "a" in the new scope to be 2.
    try expectEqual(
        HintType{ .felt = Felt252.fromInt(u8, 2) },
        scopes.getLocalVariable().?.get("a"),
    );
}

test "ExecutionScopes: exit scope" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Initialize a scope with variable "a" having value 2.
    var scope = std.StringHashMap(HintType).init(std.testing.allocator);
    try scope.put("a", .{ .felt = Felt252.fromInt(u8, 2) });

    // Append the scope to execution scopes.
    try scopes.data.append(scope);

    // Expect the count of local variables to be 1.
    try expectEqual(@as(usize, 1), scopes.getLocalVariable().?.count());
    // Expect the value of variable "a" in the current scope to be 2.
    try expectEqual(
        HintType{ .felt = Felt252.fromInt(u8, 2) },
        scopes.getLocalVariable().?.get("a"),
    );

    // Exit the current scope.
    try scopes.exitScope();

    // Check that variable `a` cannot be accessed after exiting the scope.
    try expectEqual(
        null,
        scopes.getLocalVariable().?.get("a"),
    );
    // Expect the count of local variables to be 0 after exiting the scope.
    try expectEqual(@as(usize, 0), scopes.getLocalVariable().?.count());
}

test "ExecutionScopes: assign local variable" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Assign or update variable "a" with value 2.
    try scopes.assignOrUpdateVariable("a", .{ .felt = Felt252.fromInt(u8, 2) });

    // Expect the count of local variables to be 1.
    try expectEqual(@as(usize, 1), scopes.getLocalVariable().?.count());
    // Expect the value of variable "a" to be 2.
    try expectEqual(
        HintType{ .felt = Felt252.fromInt(u8, 2) },
        scopes.getLocalVariable().?.get("a"),
    );
}

test "ExecutionScopes: re assign local variable" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Initialize a scope with variable "a" having value 2.
    var scope = std.StringHashMap(HintType).init(std.testing.allocator);
    try scope.put("a", .{ .felt = Felt252.fromInt(u8, 2) });

    // Append the scope to execution scopes.
    try scopes.data.append(scope);

    // Reassign variable "a" with value 3.
    try scopes.assignOrUpdateVariable("a", .{ .felt = Felt252.fromInt(u8, 3) });

    // Expect the count of local variables to be 1.
    try expectEqual(@as(usize, 1), scopes.getLocalVariable().?.count());
    // Expect the value of variable "a" to be 3 after reassignment.
    try expectEqual(
        HintType{ .felt = Felt252.fromInt(u8, 3) },
        scopes.getLocalVariable().?.get("a"),
    );
}

test "ExecutionScopes: delete local variable" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Initialize a scope with variable "a" having value 2.
    var scope = std.StringHashMap(HintType).init(std.testing.allocator);
    try scope.put("a", .{ .felt = Felt252.fromInt(u8, 2) });

    // Append the scope to execution scopes.
    try scopes.data.append(scope);

    // Expect that the local variable "a" exists.
    try expect(scopes.getLocalVariable().?.contains("a"));

    // Delete variable "a" from execution scopes.
    scopes.deleteVariable("a");

    // Expect that the local variable "a" does not exist after deletion.
    try expect(!scopes.getLocalVariable().?.contains("a"));
}

test "ExecutionScopes: exit main scope should return an error" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Expect an error when trying to exit the main scope.
    try expectError(ExecScopeError.ExitMainScopeError, scopes.exitScope());
}

test "ExecutionScopes: get list of u64" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Initialize a list of u64.
    var list_u64 = ArrayList(u64).init(std.testing.allocator);
    // Append values to the list.
    try list_u64.append(20);
    try list_u64.append(18);

    // Initialize a scope with the list.
    var scope = std.StringHashMap(HintType).init(std.testing.allocator);
    try scope.put("list_u64", .{ .u64_list = list_u64 });

    // Append the scope to execution scopes.
    try scopes.data.append(scope);

    // Get the list of u64 from execution scopes.
    const list = try scopes.getValue(.u64_list, "list_u64");
    // Defer the deinitialization of the list.
    defer list.deinit();

    // Expect the retrieved list to match the expected values.
    try expectEqualSlices(
        u64,
        &[_]u64{ 20, 18 },
        list.items,
    );

    // Expect an error when trying to retrieve a non-existent variable.
    try expectError(
        HintError.VariableNotInScopeError,
        scopes.getValue(.u64_list, "no_variable"),
    );

    // Get a reference to the list of u64 from execution scopes.
    const list_ref = try scopes.getValueRef(.u64_list, "list_u64");

    // Expect the retrieved reference list to match the expected values.
    try expectEqualSlices(
        u64,
        &[_]u64{ 20, 18 },
        list_ref.*.items,
    );

    // Expect an error when trying to retrieve a reference to a non-existent variable.
    try expectError(
        HintError.VariableNotInScopeError,
        scopes.getValueRef(.u64_list, "no_variable"),
    );
}

test "ExecutionScopes: get u64" {
    // Initialize execution scopes.
    var scopes = try ExecutionScopes.init(std.testing.allocator);
    // Defer the deinitialization of scopes.
    defer scopes.deinit();

    // Initialize a scope with a u64 value.
    var scope = std.StringHashMap(HintType).init(std.testing.allocator);
    try scope.put("u64", .{ .u64 = 9 });

    // Append the scope to execution scopes.
    try scopes.data.append(scope);

    // Expect to retrieve the u64 value from execution scopes.
    try expectEqual(@as(u64, 9), try scopes.getValue(.u64, "u64"));
    // Expect an error when trying to retrieve a non-existent variable.
    try expectError(HintError.VariableNotInScopeError, scopes.getValue(.u64, "no_variable"));

    // Get a reference to the u64 value from execution scopes.
    try expectEqual(@as(u64, 9), (try scopes.getValueRef(.u64, "u64")).*);
    // Expect an error when trying to retrieve a reference to a non-existent variable.
    try expectError(HintError.VariableNotInScopeError, scopes.getValueRef(.u64, "no_variable"));
}
