// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const expectEqual = @import("std").testing.expectEqual;
const Allocator = std.mem.Allocator;

// Local imports.
const relocatable = @import("relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;
const CairoVMError = @import("../error.zig").CairoVMError;
const starknet_felt = @import("../../math/fields/starknet.zig");

// Representation of the VM memory.
pub const Memory = struct {
    const Self = @This();

    // ************************************************************
    // *                        FIELDS                            *
    // ************************************************************
    /// The allocator used to allocate the memory.
    allocator: Allocator,
    // The data in the memory.
    data: std.HashMap(
        Relocatable,
        MaybeRelocatable,
        std.hash_map.AutoContext(Relocatable),
        std.hash_map.default_max_load_percentage,
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
            .data = std.AutoHashMap(
                Relocatable,
                MaybeRelocatable,
            ).init(allocator),
            .num_segments = 0,
            .validated_addresses = std.AutoHashMap(
                Relocatable,
                bool,
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
