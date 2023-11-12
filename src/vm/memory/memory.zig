// Core imports.
const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const Allocator = std.mem.Allocator;

// Local imports.
const relocatable = @import("relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;
const CairoVMError = @import("../error.zig").CairoVMError;
const starknet_felt = @import("../../math/fields/starknet.zig");
const Felt252 = starknet_felt.Felt252;

// Test imports.
const MemorySegmentManager = @import("./segments.zig").MemorySegmentManager;
const RangeCheckBuiltinRunner = @import("../builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

// Function that validates a memory address and returns a list of validated adresses
pub const validation_rule = *const fn (*Memory, Relocatable) std.ArrayList(Relocatable);

// Representation of the VM memory.
pub const Memory = struct {
    const Self = @This();

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************
    /// The allocator used to allocate the memory.
    allocator: Allocator,
    // The data in the memory.
    data: std.ArrayHashMap(
        Relocatable,
        MaybeRelocatable,
        std.array_hash_map.AutoContext(Relocatable),
        true,
    ),
    // The temporary data in the memory.
    temp_data: std.ArrayHashMap(
        Relocatable,
        MaybeRelocatable,
        std.array_hash_map.AutoContext(Relocatable),
        true,
    ),
    // The number of segments in the memory.
    num_segments: u32,
    // The number of temporary segments in the memory.
    num_temp_segments: u32,
    // Validated addresses are addresses that have been validated.
    // TODO: Consider merging this with `data` and benchmarking.
    validated_addresses: std.HashMap(
        Relocatable,
        bool,
        std.hash_map.AutoContext(Relocatable),
        std.hash_map.default_max_load_percentage,
    ),
    validation_rules: std.HashMap(
        u32,
        validation_rule,
        std.hash_map.AutoContext(u32),
        std.hash_map.default_max_load_percentage,
    ),

    // ************************************************************
    // *             MEMORY ALLOCATION AND DEALLOCATION           *
    // ************************************************************

    // Creates a new memory.
    // # Arguments
    // - `allocator` - The allocator to use.
    // # Returns
    // The new memory.
    pub fn init(allocator: Allocator) !*Self {
        var memory = try allocator.create(Self);

        memory.* = Self{
            .allocator = allocator,
            .data = std.AutoArrayHashMap(
                Relocatable,
                MaybeRelocatable,
            ).init(allocator),
            .temp_data = std.AutoArrayHashMap(Relocatable, MaybeRelocatable).init(allocator),
            .num_segments = 0,
            .num_temp_segments = 0,
            .validated_addresses = std.AutoHashMap(
                Relocatable,
                bool,
            ).init(allocator),
            .validation_rules = std.AutoHashMap(
                u32,
                validation_rule,
            ).init(allocator),
        };
        return memory;
    }

    // Safe deallocation of the memory.
    pub fn deinit(self: *Self) void {
        // Clear the hash maps
        self.data.deinit();
        self.temp_data.deinit();
        self.validated_addresses.deinit();
        // Deallocate self.
        self.allocator.destroy(self);
    }

    // ************************************************************
    // *                        METHODS                           *
    // ************************************************************

    // Inserts a value into the memory at the given address.
    // # Arguments
    // - `address` - The address to insert the value at.
    // - `value` - The value to insert.
    pub fn set(
        self: *Self,
        address: Relocatable,
        value: MaybeRelocatable,
    ) error{
        InvalidMemoryAddress,
        MemoryOutOfBounds,
    }!void {

        // Insert the value into the memory.
        if (address.segment_index < 0) {
            self.temp_data.put(address, value) catch {
                return CairoVMError.MemoryOutOfBounds;
            };
        } else {
            self.data.put(
                address,
                value,
            ) catch {
                return CairoVMError.MemoryOutOfBounds;
            };
        }
        // TODO: Add all relevant checks.
    }

    // Get some value from the memory at the given address.
    // # Arguments
    // - `address` - The address to get the value from.
    // # Returns
    // The value at the given address.
    pub fn get(
        self: *Self,
        address: Relocatable,
    ) error{MemoryOutOfBounds}!MaybeRelocatable {
        if (address.segment_index < 0) {
            return self.temp_data.get(address) orelse CairoVMError.MemoryOutOfBounds;
        }
        return self.data.get(address) orelse CairoVMError.MemoryOutOfBounds;
    }

    /// Retrieves a `Felt252` value from the memory at the specified relocatable address.
    ///
    /// This function internally calls `get` on the memory, attempting to retrieve a value at the given address.
    /// If the value is of type `Felt252`, it is returned; otherwise, an error of type `ExpectedInteger` is returned.
    ///
    /// Additionally, it handles the possibility of an out-of-bounds memory access and returns an error of type `MemoryOutOfBounds` if needed.
    ///
    /// # Arguments
    ///
    /// - `address`: The relocatable address to retrieve the `Felt252` value from.
    /// # Returns
    ///
    /// - The `Felt252` value at the specified address, or an error if not available or not of the expected type.
    pub fn getFelt(
        self: *Self,
        address: Relocatable,
    ) error{ MemoryOutOfBounds, ExpectedInteger }!Felt252 {
        return switch (try self.get(address)) {
            .felt => |fe| fe,
            else => error.ExpectedInteger,
        };
    }

    /// Retrieves a `Relocatable` value from the memory at the specified relocatable address in the Cairo VM.
    ///
    /// This function internally calls `getRelocatable` on the memory segments manager, attempting
    /// to retrieve a `Relocatable` value at the given address. It handles the possibility of an
    /// out-of-bounds memory access and returns an error if needed.
    ///
    /// # Arguments
    ///
    /// - `address`: The relocatable address to retrieve the `Relocatable` value from.
    /// # Returns
    ///
    /// - The `Relocatable` value at the specified address, or an error if not available.
    pub fn getRelocatable(
        self: *Self,
        address: Relocatable,
    ) error{ MemoryOutOfBounds, ExpectedRelocatable }!Relocatable {
        return switch (try self.get(address)) {
            .relocatable => |rel| rel,
            else => error.ExpectedRelocatable,
        };
    }

    // Adds a validation rule for a given segment.
    // # Arguments
    // - `segment_index` - The index of the segment.
    // - `rule` - The validation rule.
    pub fn addValidationRule(self: *Self, segment_index: usize, rule: validation_rule) !void {
        self.validation_rules.put(segment_index, rule);
    }
};

// Utility function to help set up memory for tests
//
// # Arguments
// - `memory` - memory to be set
// - `vals` - complile time structure with heterogenous types
fn setUpMemory(memory: *Memory, comptime vals: anytype) !void {
    inline for (vals) |row| {
        const firstCol = row[0];
        const address = Relocatable.new(firstCol[0], firstCol[1]);
        const nextCol = row[1];
        // Check number of inputs in row
        if (row[1].len == 1) {
            try memory.set(address, .{ .felt = Felt252.fromInteger(nextCol[0]) });
        } else {
            const T = @TypeOf(nextCol[0]);
            switch (@typeInfo(T)) {
                .Pointer => {
                    const num = try std.fmt.parseUnsigned(i64, nextCol[0], 10);
                    try memory.set(address, .{ .relocatable = Relocatable.new(num, nextCol[1]) });
                },
                else => {
                    try memory.set(address, .{ .relocatable = Relocatable.new(nextCol[0], nextCol[1]) });
                },
            }
        }
    }
}

test "memory inner for testing test" {
    var allocator = std.testing.allocator;

    var memory = try Memory.init(allocator);
    defer memory.deinit();

    try setUpMemory(memory, .{
        .{ .{ 1, 3 }, .{ 4, 5 } },
        .{ .{ 2, 6 }, .{ 7, 8 } },
        .{ .{ 9, 10 }, .{23} },
        .{ .{ 1, 2 }, .{ "234", 10 } },
    });

    try expectEqual(
        Felt252.fromInteger(23),
        try memory.getFelt(Relocatable.new(9, 10)),
    );

    try expectEqual(
        Relocatable.new(7, 8),
        try memory.getRelocatable(Relocatable.new(2, 6)),
    );

    try expectEqual(
        Relocatable.new(234, 10),
        try memory.getRelocatable(Relocatable.new(1, 2)),
    );
}

test "memory get without value raises error" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Get a value from the memory at an address that doesn't exist.
    try expectError(
        error.MemoryOutOfBounds,
        memory.get(Relocatable.new(0, 0)),
    );
}

test "memory set and get" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    const address_1 = Relocatable.new(
        0,
        0,
    );
    const value_1 = relocatable.fromFelt(starknet_felt.Felt252.one());

    const address_2 = Relocatable.new(
        -1,
        0,
    );
    const value_2 = relocatable.fromFelt(starknet_felt.Felt252.one());

    // Set a value into the memory.
    _ = try memory.set(
        address_1,
        value_1,
    );
    _ = try memory.set(
        address_2,
        value_2,
    );

    // Get the value from the memory.
    const maybe_value_1 = try memory.get(address_1);
    const maybe_value_2 = try memory.get(address_2);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Assert that the value is the expected value.
    try expect(maybe_value_1.eq(value_1));
    try expect(maybe_value_2.eq(value_2));
}

test "validate existing memory for range check within bound" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    var allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.new(8, 8, true);
    builtin.initializeSegments(segments);

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    const address_1 = Relocatable.new(
        0,
        0,
    );
    const value_1 = relocatable.fromFelt(starknet_felt.Felt252.one());

    // Set a value into the memory.
    _ = try memory.set(
        address_1,
        value_1,
    );

    // Get the value from the memory.
    const maybe_value_1 = try memory.get(address_1);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Assert that the value is the expected value.
    try expect(maybe_value_1.eq(value_1));
}

test "Memory: getFelt should return MemoryOutOfBounds error if no value at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    try expectError(
        error.MemoryOutOfBounds,
        memory.getFelt(Relocatable.new(10, 30)),
    );
}

test "Memory: getFelt should return Felt252 if available at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.data.put(
        Relocatable.new(10, 30),
        .{ .felt = Felt252.fromInteger(23) },
    );

    // Test checks
    try expectEqual(
        Felt252.fromInteger(23),
        try memory.getFelt(Relocatable.new(10, 30)),
    );
}

test "Memory: getFelt should return ExpectedInteger error if Relocatable instead of Felt at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.data.put(
        Relocatable.new(10, 30),
        .{ .relocatable = Relocatable.new(3, 7) },
    );

    // Test checks
    try expectError(
        error.ExpectedInteger,
        memory.getFelt(Relocatable.new(10, 30)),
    );
}

test "Memory: getRelocatable should return MemoryOutOfBounds error if no value at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    try expectError(
        error.MemoryOutOfBounds,
        memory.getRelocatable(Relocatable.new(10, 30)),
    );
}

test "Memory: getRelocatable should return Relocatable if available at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.data.put(
        Relocatable.new(10, 30),
        .{ .relocatable = Relocatable.new(4, 34) },
    );

    // Test checks
    try expectEqual(
        Relocatable.new(4, 34),
        try memory.getRelocatable(Relocatable.new(10, 30)),
    );
}

test "Memory: getRelocatable should return ExpectedRelocatable error if Felt instead of Relocatable at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.data.put(
        Relocatable.new(10, 30),
        .{ .felt = Felt252.fromInteger(3) },
    );

    // Test checks
    try expectError(
        error.ExpectedRelocatable,
        memory.getRelocatable(Relocatable.new(10, 30)),
    );
}
