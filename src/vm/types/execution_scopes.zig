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
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const DictManager = @import("../../hint_processor/dict_manager.zig").DictManager;

/// A single threaded, strong reference to a reference-counted value.
pub fn Rc(comptime T: type) type {
    return struct {
        value: *T,
        alloc: std.mem.Allocator,

        const Self = @This();
        const Inner = struct {
            strong: usize,
            weak: usize,
            value: T,

            fn innerSize() comptime_int {
                return @sizeOf(@This());
            }

            fn innerAlign() comptime_int {
                return @alignOf(@This());
            }
        };

        /// Creates a new reference-counted value.
        pub fn init(alloc: std.mem.Allocator, t: T) std.mem.Allocator.Error!Self {
            const inner = try alloc.create(Inner);
            inner.* = Inner{ .strong = 1, .weak = 1, .value = t };
            return Self{ .value = &inner.value, .alloc = alloc };
        }

        /// Constructs a new `Rc` while giving you a `Weak` to the allocation,
        /// to allow you to construct a `T` which holds a weak pointer to itself.
        pub fn initCyclic(alloc: std.mem.Allocator, comptime data_fn: fn (*Weak) T) std.mem.Allocator.Error!Self {
            const inner = try alloc.create(Inner);
            inner.* = Inner{ .strong = 0, .weak = 1, .value = undefined };

            // Strong references should collectively own a shared weak reference,
            // so don't run the destructor for our old weak reference.
            var weak = Weak{ .inner = inner, .alloc = alloc };

            // It's important we don't give up ownership of the weak pointer, or
            // else the memory might be freed by the time `data_fn` returns. If
            // we really wanted to pass ownership, we could create an additional
            // weak pointer for ourselves, but this would result in additional
            // updates to the weak reference count which might not be necessary
            // otherwise.
            inner.value = data_fn(&weak);

            std.debug.assert(inner.strong == 0);
            inner.strong = 1;

            return Self{ .value = &inner.value, .alloc = alloc };
        }

        /// Gets the number of strong references to this value.
        pub fn strongCount(self: *const Self) usize {
            return self.innerPtr().strong;
        }

        /// Gets the number of weak references to this value.
        pub fn weakCount(self: *const Self) usize {
            return self.innerPtr().weak - 1;
        }

        /// Increments the strong count.
        pub fn retain(self: *Self) Self {
            self.innerPtr().strong += 1;
            return self.*;
        }

        /// Creates a new weak reference to the pointed value
        pub fn downgrade(self: *Self) Weak {
            return Weak.init(self);
        }

        /// Decrements the reference count, deallocating if the weak count reaches zero.
        /// The continued use of the pointer after calling `release` is undefined behaviour.
        pub fn release(self: Self) void {
            const ptr = self.innerPtr();

            ptr.strong -= 1;
            if (ptr.strong == 0) {
                ptr.weak -= 1;
                if (ptr.weak == 0) {
                    self.alloc.destroy(ptr);
                }
            }
        }

        /// Decrements the reference count, deallocating the weak count reaches zero,
        /// and executing `f` if the strong count reaches zero.
        /// The continued use of the pointer after calling `release` is undefined behaviour.
        pub fn releaseWithFn(self: Self, comptime f: fn (*T) void) void {
            const ptr = self.innerPtr();

            ptr.strong -= 1;
            if (ptr.strong == 0) {
                f(self.value);
                ptr.weak -= 1;
                if (ptr.weak == 0) {
                    self.alloc.destroy(ptr);
                }
            }
        }

        /// Returns the inner value, if the `Rc` has exactly one strong reference.
        /// Otherwise, `null` is returned.
        /// This will succeed even if there are outstanding weak references.
        /// The continued use of the pointer if the method successfully returns `T` is undefined behaviour.
        pub fn tryUnwrap(self: Self) ?T {
            const ptr = self.innerPtr();

            if (ptr.strong == 1) {
                ptr.strong = 0;
                const tmp = self.value.*;

                ptr.weak -= 1;
                if (ptr.weak == 0) {
                    self.alloc.destroy(ptr);
                }

                return tmp;
            }

            return null;
        }

        /// Total size (in bytes) of the reference counted value on the heap.
        /// This value accounts for the extra memory required to count the references.
        pub fn innerSize() comptime_int {
            return Inner.innerSize();
        }

        /// Alignment (in bytes) of the reference counted value on the heap.
        /// This value accounts for the extra memory required to count the references.
        pub fn innerAlign() comptime_int {
            return Inner.innerAlign();
        }

        inline fn innerPtr(self: *const Self) *Inner {
            return @fieldParentPtr(Inner, "value", self.value);
        }

        /// A single threaded, weak reference to a reference-counted value.
        pub const Weak = struct {
            inner: ?*Inner = null,
            alloc: std.mem.Allocator,

            /// Creates a new weak reference.
            pub fn init(parent: *Rc(T)) Weak {
                const ptr = parent.innerPtr();
                ptr.weak += 1;
                return Weak{ .inner = ptr, .alloc = parent.alloc };
            }

            /// Creates a new weak reference object from a pointer to it's underlying value,
            /// without increasing the weak count.
            pub fn fromValuePtr(value: *T, alloc: std.mem.Allocator) Weak {
                return .{ .inner = @fieldParentPtr(Inner, "value", value), .alloc = alloc };
            }

            /// Gets the number of strong references to this value.
            pub fn strongCount(self: *const Weak) usize {
                return (self.innerPtr() orelse return 0).strong;
            }

            /// Gets the number of weak references to this value.
            pub fn weakCount(self: *const Weak) usize {
                const ptr = self.innerPtr() orelse return 1;
                if (ptr.strong == 0) {
                    return ptr.weak;
                } else {
                    return ptr.weak - 1;
                }
            }

            /// Increments the weak count.
            pub fn retain(self: *Weak) Weak {
                if (self.innerPtr()) |ptr| {
                    ptr.weak += 1;
                }
                return self.*;
            }

            /// Attempts to upgrade the weak pointer to an `Rc`, delaying dropping of the inner value if successful.
            ///
            /// Returns `null` if the inner value has since been dropped.
            pub fn upgrade(self: *Weak) ?Rc(T) {
                const ptr = self.innerPtr() orelse return null;

                if (ptr.strong == 0) {
                    ptr.weak -= 1;
                    if (ptr.weak == 0) {
                        self.alloc.destroy(ptr);
                        self.inner = null;
                    }
                    return null;
                }

                ptr.strong += 1;
                return Rc(T){
                    .value = &ptr.value,
                    .alloc = self.alloc,
                };
            }

            /// Decrements the weak reference count, deallocating if it reaches zero.
            /// The continued use of the pointer after calling `release` is undefined behaviour.
            pub fn release(self: Weak) void {
                if (self.innerPtr()) |ptr| {
                    ptr.weak -= 1;
                    if (ptr.weak == 0) {
                        self.alloc.destroy(ptr);
                    }
                }
            }

            /// Total size (in bytes) of the reference counted value on the heap.
            /// This value accounts for the extra memory required to count the references,
            /// and is valid for single and multi-threaded refrence counters.
            pub fn innerSize() comptime_int {
                return Inner.innerSize();
            }

            /// Alignment (in bytes) of the reference counted value on the heap.
            /// This value accounts for the extra memory required to count the references,
            /// and is valid for single and multi-threaded refrence counters.
            pub fn innerAlign() comptime_int {
                return Inner.innerAlign();
            }

            inline fn innerPtr(self: *const Weak) ?*Inner {
                return @as(?*Inner, @ptrCast(self.inner));
            }
        };
    };
}

/// Represents the possible types of variables in the hint scope.
pub const HintType = union(enum) {
    const Self = @This();
    // TODO: Add missing types
    felt: Felt252,
    u64: u64,
    u64_list: ArrayList(u64),
    felt_map_of_u64_list: std.AutoHashMap(Felt252, std.ArrayList(u64)),
    maybe_relocatable_map: std.AutoHashMap(MaybeRelocatable, MaybeRelocatable),
    dict_manager: Rc(DictManager),

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .felt_map_of_u64_list => |*d| {
                var it = d.valueIterator();
                while (it.next()) |v| v.deinit();

                d.deinit();
            },
            .maybe_relocatable_map => |*m| m.deinit(),
            .u64_list => |*a| a.deinit(),
            .dict_manager => |d| d.releaseWithFn(DictManager.deinit),
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

            while (it.next()) |h| {
                h.deinit();
            }

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

    pub fn getDictManager(self: *Self) !Rc(DictManager) {
        var dict_manager_rc = try self.getValue(.dict_manager, "dict_manager");
        return dict_manager_rc.retain();
    }

    /// Returns the value in the current execution scope that matches the name and is of the given type.
    pub fn getValue(
        self: *const Self,
        comptime T: std.meta.Tag(HintType),
        name: []const u8,
    ) !std.meta.TagPayload(HintType, T) {
        const val = try self.get(name);

        if (std.meta.activeTag(val) == T) return @field(val, @tagName(T));

        return HintError.VariableNotInScopeError;
    }

    /// Returns a reference to the value in the current execution scope that matches the name and is of the given type.
    pub fn getValueRef(
        self: *const Self,
        comptime T: std.meta.Tag(HintType),
        name: []const u8,
    ) !*std.meta.TagPayload(HintType, T) {
        const val = try self.getRef(name);

        if (std.meta.activeTag(val.*) == T) return &@field(val.*, @tagName(T));

        return HintError.VariableNotInScopeError;
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
    var list = try scopes.getValueRef(.u64_list, "list_u64");
    // verifing get value by ref
    try list.append(17);
    try list.append(16);

    const list_val = try scopes.getValue(.u64_list, "list_u64");
    // Expect the retrieved list to match the expected values.
    try expectEqualSlices(
        u64,
        &[_]u64{ 20, 18, 17, 16 },
        list_val.items,
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
        &[_]u64{ 20, 18, 17, 16 },

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
