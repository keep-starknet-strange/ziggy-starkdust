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
    // The number of segments in the memory.
    num_segments: u32,
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
            .num_segments = 0,
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

        // Check if the address is valid.
        if (address.segment_index < 0) {
            return CairoVMError.InvalidMemoryAddress;
        }

        // Insert the value into the memory.
        self.data.put(
            address,
            value,
        ) catch {
            return CairoVMError.MemoryOutOfBounds;
        };

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

    // Adds a validation rule for a given segment.
    // # Arguments
    // - `segment_index` - The index of the segment.
    // - `rule` - The validation rule.
    pub fn addValidationRule(self: *Self, segment_index: usize, rule: validation_rule) !void {
        self.validation_rules.put(segment_index, rule);
    }
};

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
    _ = memory.get(Relocatable.new(
        0,
        0,
    )) catch |err| {
        // Assert that the error is the expected error.
        try expect(err == error.MemoryOutOfBounds);
        return;
    };
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
