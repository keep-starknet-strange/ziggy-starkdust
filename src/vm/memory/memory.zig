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
const MemoryError = @import("../error.zig").MemoryError;
const starknet_felt = @import("../../math/fields/starknet.zig");
const Felt252 = starknet_felt.Felt252;

// Test imports.
const MemorySegmentManager = @import("./segments.zig").MemorySegmentManager;
const RangeCheckBuiltinRunner = @import("../builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;
// Function that validates a memory address and returns a list of validated adresses
pub const validation_rule = *const fn (*Memory, Relocatable) std.ArrayList(Relocatable);

pub const MemoryCell = struct {
    const Self = @This();

    maybe_relocatable: MaybeRelocatable,
    is_accessed: bool,

    // Creates a new MemoryCell.
    // # Arguments
    // - maybe_relocatable - The index of the memory segment.
    // # Returns
    // A new MemoryCell.
    pub fn new(
        maybe_relocatable: MaybeRelocatable,
    ) Self {
        return .{
            .maybe_relocatable = maybe_relocatable,
            .is_accessed = false,
        };
    }

    // Marks Memory Cell as accessed.
    pub fn markAccessed(self: *Self) void {
        self.is_accessed = true;
    }
};

/// Represents a set of validated memory addresses in the Cairo VM.
pub const AddressSet = struct {
    const Self = @This();

    /// Internal hash map storing the validated addresses and their accessibility status.
    set: std.HashMap(
        Relocatable,
        bool,
        std.hash_map.AutoContext(Relocatable),
        std.hash_map.default_max_load_percentage,
    ),

    /// Initializes a new AddressSet using the provided allocator.
    ///
    /// # Arguments
    /// - `allocator`: The allocator used for set initialization.
    /// # Returns
    /// A new AddressSet instance.
    pub fn init(allocator: Allocator) Self {
        return .{ .set = std.AutoHashMap(Relocatable, bool).init(allocator) };
    }

    /// Checks if the set contains the specified memory address.
    ///
    /// # Arguments
    /// - `address`: The memory address to check.
    /// # Returns
    /// `true` if the address is in the set and accessible, otherwise `false`.
    pub fn contains(self: *Self, address: Relocatable) bool {
        if (address.segment_index < 0) {
            return false;
        }
        return self.set.get(address) orelse false;
    }

    /// Adds an array of memory addresses to the set, ignoring addresses with negative segment indexes.
    ///
    /// # Arguments
    /// - `addresses`: An array of memory addresses to add to the set.
    /// # Returns
    /// An error if the addition fails.
    pub fn addAddresses(self: *Self, addresses: []const Relocatable) !void {
        for (addresses) |address| {
            if (address.segment_index < 0) {
                continue;
            }
            try self.set.put(address, true);
        }
    }

    /// Returns the number of validated addresses in the set.
    ///
    /// # Returns
    /// The count of validated addresses in the set.
    pub fn len(self: *Self) u32 {
        return self.set.count();
    }

    /// Safely deallocates the memory used by the set.
    pub fn deinit(self: *Self) void {
        self.set.deinit();
    }
};

// Representation of the VM memory.
pub const Memory = struct {
    const Self = @This();

    /// Allocator responsible for memory allocation within the VM memory.
    allocator: Allocator,
    /// Hash map storing the main data in the memory, indexed by Relocatable addresses.
    data: std.ArrayHashMap(
        Relocatable,
        MemoryCell,
        std.array_hash_map.AutoContext(Relocatable),
        true,
    ),
    /// Hash map storing temporary data in the memory, indexed by Relocatable addresses.
    temp_data: std.ArrayHashMap(
        Relocatable,
        MemoryCell,
        std.array_hash_map.AutoContext(Relocatable),
        true,
    ),
    /// Number of segments currently present in the memory.
    num_segments: u32,
    /// Number of temporary segments in the memory.
    num_temp_segments: u32,
    /// Hash map tracking validated addresses to ensure they have been properly validated.
    /// Consideration: Possible merge with `data` for optimization; benchmarking recommended.
    validated_addresses: AddressSet,
    /// Hash map linking temporary data indices to their corresponding relocation rules.
    /// Keys are derived from temp_data's indices (segment_index), starting at zero.
    /// For example, segment_index = -1 maps to key 0, -2 to key 1, and so on.
    relocation_rules: std.HashMap(
        u64,
        Relocatable,
        std.hash_map.AutoContext(u64),
        std.hash_map.default_max_load_percentage,
    ),
    /// Hash map associating segment indices with their respective validation rules.
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
                MemoryCell,
            ).init(allocator),
            .temp_data = std.AutoArrayHashMap(Relocatable, MemoryCell).init(allocator),
            .num_segments = 0,
            .num_temp_segments = 0,
            .validated_addresses = AddressSet.init(allocator),
            .relocation_rules = std.AutoHashMap(
                u64,
                Relocatable,
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
        self.validation_rules.deinit();
        self.relocation_rules.deinit();
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
            self.temp_data.put(address, MemoryCell.new(value)) catch {
                return CairoVMError.MemoryOutOfBounds;
            };
        } else {
            self.data.put(
                address,
                MemoryCell.new(value),
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
            if (self.temp_data.get(address) == null) {
                return CairoVMError.MemoryOutOfBounds;
            } else {
                return self.temp_data.get(address).?.maybe_relocatable;
            }
        } else {
            if (self.data.get(address) == null) {
                return CairoVMError.MemoryOutOfBounds;
            } else {
                return self.data.get(address).?.maybe_relocatable;
            }
        }
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

    /// Marks a `MemoryCell` as accessed at the specified relocatable address.
    /// # Arguments
    /// - `address` - The relocatable address to mark.
    pub fn markAsAccessed(self: *Self, address: Relocatable) void {
        if (address.segment_index < 0) {
            var tempCell = self.temp_data.getPtr(address).?;
            tempCell.markAccessed();
        } else {
            var cell = self.data.getPtr(address).?;
            cell.markAccessed();
        }
    }

    /// Adds a relocation rule to the VM memory, allowing redirection of temporary data to a specified destination.
    ///
    /// # Arguments
    /// - `src_ptr`: The source Relocatable pointer representing the temporary segment to be relocated.
    /// - `dst_ptr`: The destination Relocatable pointer where the temporary segment will be redirected.
    ///
    /// # Returns
    /// This function returns an error if the relocation fails due to invalid conditions.
    pub fn addRelocationRule(
        self: *Self,
        src_ptr: Relocatable,
        dst_ptr: Relocatable,
    ) !void {
        // Check if the source pointer is in a temporary segment.
        if (src_ptr.segment_index >= 0) {
            return MemoryError.AddressNotInTemporarySegment;
        }
        // Check if the source pointer has a non-zero offset.
        if (src_ptr.offset != 0) {
            return MemoryError.NonZeroOffset;
        }
        // Adjust the segment index to begin at zero.
        const segment_index: u64 = @intCast(-(src_ptr.segment_index + 1));
        // Check for duplicated relocation rules.
        if (self.relocation_rules.contains(segment_index)) {
            return MemoryError.DuplicatedRelocation;
        }
        // Add the relocation rule to the memory.
        try self.relocation_rules.put(segment_index, dst_ptr);
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
        MemoryCell.new(.{ .felt = Felt252.fromInteger(23) }),
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
        MemoryCell.new(MaybeRelocatable{ .relocatable = Relocatable.new(3, 7) }),
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
        MemoryCell.new(MaybeRelocatable{ .relocatable = Relocatable.new(4, 34) }),
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
        MemoryCell.new(.{ .felt = Felt252.fromInteger(3) }),
    );

    // Test checks
    try expectError(
        error.ExpectedRelocatable,
        memory.getRelocatable(Relocatable.new(10, 30)),
    );
}

test "Memory: markAsAccessed should mark memory cell" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    var relo = Relocatable.new(1, 3);
    try setUpMemory(memory, .{
        .{ .{ 1, 3 }, .{ 4, 5 } },
    });

    memory.markAsAccessed(relo);
    // Test checks
    try expectEqual(
        true,
        memory.data.get(relo).?.is_accessed,
    );
}


test "Memory: addRelocationRule should return an error if source segment index >= 0" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    // Check if source pointer segment index is positive
    try expectError(
        MemoryError.AddressNotInTemporarySegment,
        memory.addRelocationRule(
            Relocatable.new(1, 3),
            Relocatable.new(4, 7),
        ),
    );
    // Check if source pointer segment index is zero
    try expectError(
        MemoryError.AddressNotInTemporarySegment,
        memory.addRelocationRule(
            Relocatable.new(0, 3),
            Relocatable.new(4, 7),
        ),
    );
}

test "Memory: addRelocationRule should return an error if source offset is not zero" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    // Check if source offset is not zero
    try expectError(
        MemoryError.NonZeroOffset,
        memory.addRelocationRule(
            Relocatable.new(-2, 3),
            Relocatable.new(4, 7),
        ),
    );
}

test "Memory: addRelocationRule should return an error if another relocation present at same index" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.relocation_rules.put(1, Relocatable.new(9, 77));

    // Test checks
    try expectError(
        MemoryError.DuplicatedRelocation,
        memory.addRelocationRule(
            Relocatable.new(-2, 0),
            Relocatable.new(4, 7),
        ),
    );
}

test "Memory: addRelocationRule should add new relocation rule" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    _ = try memory.addRelocationRule(
        Relocatable.new(-2, 0),
        Relocatable.new(4, 7),
    );

    // Test checks
    // Verify that relocation rule content is correct
    try expectEqual(
        @as(u32, 1),
        memory.relocation_rules.count(),
    );
    // Verify that new relocation rule was added properly
    try expectEqual(
        Relocatable.new(4, 7),
        memory.relocation_rules.get(1).?,
    );
}
