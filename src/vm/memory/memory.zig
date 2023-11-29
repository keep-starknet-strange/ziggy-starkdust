// Core imports.
const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;
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
pub const validation_rule = *const fn (*Memory, Relocatable) ?[]const Relocatable;

pub const MemoryCell = struct {
    /// Represents a memory cell that holds relocation information and access status.
    const Self = @This();
    /// The index or relocation information of the memory segment.
    maybe_relocatable: MaybeRelocatable,
    /// Indicates whether the MemoryCell has been accessed.
    is_accessed: bool,

    /// Creates a new MemoryCell.
    ///
    /// # Arguments
    /// - `maybe_relocatable`: The index or relocation information of the memory segment.
    /// # Returns
    /// A new MemoryCell.
    pub fn new(
        maybe_relocatable: MaybeRelocatable,
    ) Self {
        return .{
            .maybe_relocatable = maybe_relocatable,
            .is_accessed = false,
        };
    }

    /// Marks the MemoryCell as accessed.
    ///
    /// # Safety
    /// This function marks the MemoryCell as accessed, indicating it has been used or read.
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
    /// ArrayList storing the main data in the memory, indexed by Relocatable addresses.
    data: std.ArrayList(std.ArrayListUnmanaged(?MemoryCell)),
    /// ArrayList storing temporary data in the memory, indexed by Relocatable addresses.
    temp_data: std.ArrayList(std.ArrayListUnmanaged(?MemoryCell)),
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
        const memory = try allocator.create(Self);

        memory.* = Self{
            .allocator = allocator,
            .data = std.ArrayList(std.ArrayListUnmanaged(?MemoryCell)).init(allocator),
            .temp_data = std.ArrayList(std.ArrayListUnmanaged(?MemoryCell)).init(allocator),
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

    /// Safely deallocates memory, clearing internal data structures and deallocating 'self'.
    /// # Safety
    /// This function safely deallocates memory managed by 'self', clearing internal data structures
    /// and deallocating the memory for the instance.
    pub fn deinit(self: *Self) void {
        self.data.deinit();
        self.temp_data.deinit();
        self.validated_addresses.deinit();
        self.validation_rules.deinit();
        self.relocation_rules.deinit();
        self.allocator.destroy(self);
    }

    /// Safely deallocates memory within 'data' and 'temp_data' using the provided 'allocator'.
    /// # Arguments
    /// - `allocator` - The allocator to use for deallocation.
    /// # Safety
    /// This function safely deallocates memory within 'data' and 'temp_data'
    /// using the provided 'allocator'.
    pub fn deinitData(self: *Self, allocator: Allocator) void {
        for (self.data.items) |*v| {
            v.deinit(allocator);
        }
        for (self.temp_data.items) |*v| {
            v.deinit(allocator);
        }
    }

    // Inserts a value into the memory at the given address.
    // # Arguments
    // - `address` - The address to insert the value at.
    // - `value` - The value to insert.
    pub fn set(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        value: MaybeRelocatable,
    ) !void {
        var data = if (address.segment_index < 0) &self.temp_data else &self.data;
        const segment_index: usize = @intCast(if (address.segment_index < 0) -(address.segment_index + 1) else address.segment_index);

        if (data.items.len <= segment_index) {
            return MemoryError.UnallocatedSegment;
        }

        if (data.items.len <= @as(usize, segment_index)) {
            try data.appendNTimes(
                std.ArrayListUnmanaged(?MemoryCell){},
                @as(usize, segment_index) + 1 - data.items.len,
            );
        }

        var data_segment = &data.items[segment_index];

        if (data_segment.items.len <= @as(usize, @intCast(address.offset))) {
            try data_segment.appendNTimes(
                allocator,
                null,
                @as(usize, @intCast(address.offset)) + 1 - data_segment.items.len,
            );
        }

        // check if existing memory, cannot overwrite
        if (data_segment.items[@as(usize, @intCast(address.offset))] != null) {
            if (data_segment.items[@intCast(address.offset)]) |item| {
                if (!item.maybe_relocatable.eq(value)) {
                    return MemoryError.DuplicatedRelocation;
                }
            }
        }
        data_segment.items[address.offset] = MemoryCell.new(value);
    }

    // Get some value from the memory at the given address.
    // # Arguments
    // - `address` - The address to get the value from.
    // # Returns
    // The value at the given address.
    pub fn get(
        self: *Self,
        address: Relocatable,
    ) error{MemoryOutOfBounds}!?MaybeRelocatable {
        const data = if (address.segment_index < 0) &self.temp_data else &self.data;
        const segment_index: usize = @intCast(if (address.segment_index < 0) -(address.segment_index + 1) else address.segment_index);

        const isSegmentIndexValid = address.segment_index < data.items.len;
        const isOffsetValid = isSegmentIndexValid and (address.offset < data.items[segment_index].items.len);

        if (!isSegmentIndexValid or !isOffsetValid) {
            return CairoVMError.MemoryOutOfBounds;
        }

        if (data.items[segment_index].items[@intCast(address.offset)]) |val| {
            return val.maybe_relocatable;
        }
        return null;
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
        if (try self.get(address)) |m| {
            return switch (m) {
                .felt => |fe| fe,
                else => error.ExpectedInteger,
            };
        } else {
            return error.ExpectedInteger;
        }
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
        if (try self.get(address)) |m| {
            return switch (m) {
                .relocatable => |rel| rel,
                else => error.ExpectedRelocatable,
            };
        } else {
            return error.ExpectedRelocatable;
        }
    }

    // Adds a validation rule for a given segment.
    // # Arguments
    // - `segment_index` - The index of the segment.
    // - `rule` - The validation rule.
    pub fn addValidationRule(self: *Self, segment_index: usize, rule: validation_rule) !void {
        try self.validation_rules.put(@intCast(segment_index), rule);
    }

    /// Marks a `MemoryCell` as accessed at the specified relocatable address within the memory segment.
    ///
    /// # Description
    /// This function marks a memory cell as accessed at the provided relocatable address within the memory segment.
    /// It enables tracking and management of memory access for effective memory handling within the Cairo VM.
    ///
    /// # Arguments
    /// - `address` - The relocatable address to mark as accessed within the memory segment.
    ///
    /// # Safety
    /// This function assumes correct usage and does not perform bounds checking. It's the responsibility of the caller
    /// to ensure that the provided `address` is within the valid bounds of the memory segment.
    pub fn markAsAccessed(self: *Self, address: Relocatable) void {
        const segment_index: usize = @intCast(if (address.segment_index < 0) -(address.segment_index + 1) else address.segment_index);
        var data = if (address.segment_index < 0) &self.temp_data else &self.data;

        if (segment_index < data.items.len) {
            if (address.offset < data.items[segment_index].items.len) {
                if (data.items[segment_index].items[address.offset] != null)
                    data.items[segment_index].items[address.offset].?.is_accessed = true;
            }
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

    /// Adds a validated memory cell to the VM memory.
    ///
    /// # Arguments
    /// - `address`: The source Relocatable address of the memory cell to be checked.
    ///
    /// # Returns
    /// This function returns an error if the validation fails due to invalid conditions.
    pub fn validateMemoryCell(self: *Self, address: Relocatable) !void {
        if (self.validation_rules.get(@intCast(address.segment_index))) |rule| {
            if (!self.validated_addresses.contains(address)) {
                if (rule(self, address)) |list| {
                    _ = list;
                    // TODO: debug rangeCheckValidationRule to be able to push list here again
                    try self.validated_addresses.addAddresses(&[_]Relocatable{address});
                }
            }
        }
    }

    /// Applies validation_rules to every memory address
    ///
    /// # Returns
    /// This function returns an error if the validation fails due to invalid conditions.
    pub fn validateExistingMemory(self: *Self) !void {
        for (self.data.items, 0..) |row, i| {
            for (row.items, 0..) |cell, j| {
                if (cell != null) {
                    try self.validateMemoryCell(Relocatable.new(@intCast(i), j));
                }
            }
        }
    }

    /// Retrieves a range of memory values starting from a specified address.
    ///
    /// # Arguments
    ///
    /// * `allocator`: The allocator used for the memory allocation of the returned list.
    /// * `address`: The starting address in the memory from which the range is retrieved.
    /// * `size`: The size of the range to be retrieved.
    ///
    /// # Returns
    ///
    /// Returns a list containing memory values retrieved from the specified range starting at the given address.
    /// The list may contain `null` elements for inaccessible memory positions.
    ///
    /// # Errors
    ///
    /// Returns an error if there are any issues encountered during the retrieval of the memory range.
    pub fn getRange(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        size: usize,
    ) !std.ArrayList(?MaybeRelocatable) {
        var values = std.ArrayList(?MaybeRelocatable).init(allocator);
        for (0..size) |i| {
            try values.append(try self.get(try address.addUint(@intCast(i))));
        }
        return values;
    }

    /// Counts the number of accessed addresses within a specified segment in the VM memory.
    ///
    /// # Arguments
    ///
    /// * `segment_index`: The index of the segment for which accessed addresses are counted.
    ///
    /// # Returns
    ///
    /// Returns the count of accessed addresses within the specified segment if it exists within the VM memory.
    /// Returns `None` if the provided segment index exceeds the available segments in the VM memory.
    pub fn countAccessedAddressesInSegment(self: *Self, segment_index: usize) ?usize {
        if (segment_index < self.data.items.len) {
            var count: usize = 0;
            for (self.data.items[segment_index].items) |item| {
                if (item) |i| {
                    if (i.is_accessed) count += 1;
                }
            }
            return count;
        }
        return null;
    }
};

// Utility function to help set up memory for tests
//
// # Arguments
// - `memory` - memory to be set
// - `vals` - complile time structure with heterogenous types
pub fn setUpMemory(memory: *Memory, allocator: Allocator, comptime vals: anytype) !void {
    const segment = std.ArrayListUnmanaged(?MemoryCell){};
    var si: usize = 0;
    inline for (vals) |row| {
        if (row[0][0] < 0) {
            si = @intCast(-(row[0][0] + 1));
            while (si >= memory.num_temp_segments) {
                try memory.temp_data.append(segment);
                memory.num_temp_segments += 1;
            }
        } else {
            si = @intCast(row[0][0]);
            while (si >= memory.num_segments) {
                try memory.data.append(segment);
                memory.num_segments += 1;
            }
        }
        // Check number of inputs in row
        if (row[1].len == 1) {
            try memory.set(
                allocator,
                Relocatable.new(row[0][0], row[0][1]),
                .{ .felt = Felt252.fromInteger(row[1][0]) },
            );
        } else {
            switch (@typeInfo(@TypeOf(row[1][0]))) {
                .Pointer => {
                    try memory.set(
                        allocator,
                        Relocatable.new(row[0][0], row[0][1]),
                        .{ .relocatable = Relocatable.new(
                            try std.fmt.parseUnsigned(i64, row[1][0], 10),
                            row[1][1],
                        ) },
                    );
                },
                else => {
                    try memory.set(
                        allocator,
                        Relocatable.new(row[0][0], row[0][1]),
                        .{ .relocatable = Relocatable.new(row[1][0], row[1][1]) },
                    );
                },
            }
        }
    }
}

test "Memory: validate existing memory" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.new(8, 8, true);
    try builtin.initializeSegments(segments);
    try builtin.addValidationRule(segments.memory);

    try setUpMemory(segments.memory, std.testing.allocator, .{
        .{ .{ 0, 2 }, .{1} },
        .{ .{ 0, 5 }, .{1} },
        .{ .{ 0, 7 }, .{1} },
        .{ .{ 1, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
    });
    defer segments.memory.deinitData(std.testing.allocator);

    try segments.memory.validateExistingMemory();

    try expect(
        segments.memory.validated_addresses.contains(Relocatable.new(0, 2)),
    );
    try expect(
        segments.memory.validated_addresses.contains(Relocatable.new(0, 5)),
    );
    try expect(
        segments.memory.validated_addresses.contains(Relocatable.new(0, 7)),
    );
    try expectEqual(
        false,
        segments.memory.validated_addresses.contains(Relocatable.new(1, 1)),
    );
    try expectEqual(
        false,
        segments.memory.validated_addresses.contains(Relocatable.new(2, 2)),
    );
}

test "Memory: validate memory cell" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.new(8, 8, true);
    try builtin.initializeSegments(segments);
    try builtin.addValidationRule(segments.memory);

    try setUpMemory(
        segments.memory,
        std.testing.allocator,
        .{.{ .{ 0, 1 }, .{1} }},
    );

    try segments.memory.validateMemoryCell(Relocatable.new(0, 1));
    // null case
    try segments.memory.validateMemoryCell(Relocatable.new(0, 7));
    defer segments.memory.deinitData(std.testing.allocator);

    try expectEqual(
        true,
        segments.memory.validated_addresses.contains(Relocatable.new(0, 1)),
    );
    try expectEqual(
        false,
        segments.memory.validated_addresses.contains(Relocatable.new(0, 7)),
    );
}

test "Memory: validate memory cell segment index not in validation rules" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.new(8, 8, true);
    try builtin.initializeSegments(segments);

    try setUpMemory(
        segments.memory,
        std.testing.allocator,
        .{.{ .{ 0, 1 }, .{1} }},
    );

    try segments.memory.validateMemoryCell(Relocatable.new(0, 1));
    defer segments.memory.deinitData(std.testing.allocator);

    try expectEqual(
        segments.memory.validated_addresses.contains(Relocatable.new(0, 1)),
        false,
    );
}

test "Memory: validate memory cell already exist in validation rules" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.new(8, 8, true);
    try builtin.initializeSegments(segments);
    try builtin.addValidationRule(segments.memory);

    try segments.memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});
    const seg = segments.addSegment();
    _ = try seg;

    try segments.memory.set(std.testing.allocator, Relocatable.new(0, 1), MaybeRelocatable.fromFelt(starknet_felt.Felt252.one()));
    defer segments.memory.deinitData(std.testing.allocator);

    try segments.memory.validateMemoryCell(Relocatable.new(0, 1));

    try expectEqual(
        segments.memory.validated_addresses.contains(Relocatable.new(0, 1)),
        true,
    );

    //attempt to validate memory cell a second time
    try segments.memory.validateMemoryCell(Relocatable.new(0, 1));

    try expectEqual(
        segments.memory.validated_addresses.contains(Relocatable.new(0, 1)),
        // should stay true
        true,
    );
}

test "memory inner for testing test" {
    const allocator = std.testing.allocator;

    var memory = try Memory.init(allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 1, 3 }, .{ 4, 5 } },
            .{ .{ 1, 2 }, .{ "234", 10 } },
            .{ .{ 2, 6 }, .{ 7, 8 } },
            .{ .{ 9, 10 }, .{23} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

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
    const allocator = std.testing.allocator;

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
    const allocator = std.testing.allocator;

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
    const value_1 = MaybeRelocatable.fromFelt(starknet_felt.Felt252.one());

    const address_2 = Relocatable.new(
        -1,
        0,
    );
    const value_2 = MaybeRelocatable.fromFelt(starknet_felt.Felt252.one());

    // Set a value into the memory.
    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ -1, 0 }, .{1} },
        },
    );

    defer memory.deinitData(std.testing.allocator);

    // Get the value from the memory.
    const maybe_value_1 = try memory.get(address_1);
    const maybe_value_2 = try memory.get(address_2);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Assert that the value is the expected value.
    try expect(maybe_value_1.?.eq(value_1));
    try expect(maybe_value_2.?.eq(value_2));
}

test "Memory: get inside a segment without value but inbout should return null" {
    // Test setup
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    // Test body
    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{5} },
            .{ .{ 1, 1 }, .{2} },
            .{ .{ 1, 5 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test check
    try expectEqual(
        @as(?MaybeRelocatable, null),
        try memory.get(Relocatable.new(1, 3)),
    );
}

test "Memory: set where number of segments is less than segment index should return UnallocatedSegment error" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    try setUpMemory(
        segments.memory,
        std.testing.allocator,
        .{.{ .{ 0, 1 }, .{1} }},
    );

    try expectError(MemoryError.UnallocatedSegment, segments.memory.set(allocator, Relocatable.new(3, 1), .{ .felt = Felt252.fromInteger(3) }));
    defer segments.memory.deinitData(std.testing.allocator);
}

test "validate existing memory for range check within bound" {
    // ************************************************************
    // *                 SETUP TEST CONTEXT                       *
    // ************************************************************
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.new(8, 8, true);
    try builtin.initializeSegments(segments);

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    const address_1 = Relocatable.new(
        0,
        0,
    );
    const value_1 = MaybeRelocatable.fromFelt(starknet_felt.Felt252.one());

    // Set a value into the memory.
    try setUpMemory(
        memory,
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{1} }},
    );

    defer memory.deinitData(std.testing.allocator);

    // Get the value from the memory.
    const maybe_value_1 = try memory.get(address_1);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Assert that the value is the expected value.
    try expect(maybe_value_1.?.eq(value_1));
}

test "Memory: getFelt should return MemoryOutOfBounds error if no value at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    try expectError(
        error.MemoryOutOfBounds,
        memory.getFelt(Relocatable.new(0, 0)),
    );
}

test "Memory: getFelt should return Felt252 if available at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{23} }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectEqual(
        Felt252.fromInteger(23),
        try memory.getFelt(Relocatable.new(0, 0)),
    );
}

test "Memory: getFelt should return ExpectedInteger error if Relocatable instead of Felt at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{ 3, 7 } }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        error.ExpectedInteger,
        memory.getFelt(Relocatable.new(0, 0)),
    );
}

test "Memory: getRelocatable should return MemoryOutOfBounds error if no value at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    try expectError(
        error.MemoryOutOfBounds,
        memory.getRelocatable(Relocatable.new(0, 0)),
    );
}

test "Memory: getRelocatable should return Relocatable if available at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{ 4, 34 } }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectEqual(
        Relocatable.new(4, 34),
        try memory.getRelocatable(Relocatable.new(0, 0)),
    );
}

test "Memory: getRelocatable should return ExpectedRelocatable error if Felt instead of Relocatable at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{3} }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        error.ExpectedRelocatable,
        memory.getRelocatable(Relocatable.new(0, 0)),
    );
}

test "Memory: markAsAccessed should mark memory cell" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    const relo = Relocatable.new(0, 3);

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{.{ .{ 0, 3 }, .{ 4, 5 } }},
    );
    defer memory.deinitData(std.testing.allocator);

    memory.markAsAccessed(relo);
    // Test checks
    try expectEqual(
        true,
        memory.data.items[0].items[3].?.is_accessed,
    );
}

test "Memory: markAsAccessed should not panic if non existing segment" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    memory.markAsAccessed(Relocatable.new(10, 0));
}

test "Memory: markAsAccessed should not panic if non existing offset" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{.{ .{ 1, 3 }, .{ 4, 5 } }},
    );
    defer memory.deinitData(std.testing.allocator);

    memory.markAsAccessed(Relocatable.new(1, 17));
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

test "Memory: getRange for continuous memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{2} },
            .{ .{ 1, 1 }, .{3} },
            .{ .{ 1, 2 }, .{4} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    var expected_vec = std.ArrayList(?MaybeRelocatable).init(std.testing.allocator);
    defer expected_vec.deinit();

    try expected_vec.append(MaybeRelocatable.fromU256(2));
    try expected_vec.append(MaybeRelocatable.fromU256(3));
    try expected_vec.append(MaybeRelocatable.fromU256(4));

    var actual = try memory.getRange(
        std.testing.allocator,
        Relocatable.new(1, 0),
        3,
    );
    defer actual.deinit();

    // Test checks
    try expectEqualSlices(
        ?MaybeRelocatable,
        expected_vec.items,
        actual.items,
    );
}

test "Memory: getRange for non continuous memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{2} },
            .{ .{ 1, 1 }, .{3} },
            .{ .{ 1, 3 }, .{4} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    var expected_vec = std.ArrayList(?MaybeRelocatable).init(std.testing.allocator);
    defer expected_vec.deinit();

    try expected_vec.append(MaybeRelocatable.fromU256(2));
    try expected_vec.append(MaybeRelocatable.fromU256(3));
    try expected_vec.append(null);
    try expected_vec.append(MaybeRelocatable.fromU256(4));

    var actual = try memory.getRange(
        std.testing.allocator,
        Relocatable.new(1, 0),
        4,
    );
    defer actual.deinit();

    // Test checks
    try expectEqualSlices(
        ?MaybeRelocatable,
        expected_vec.items,
        actual.items,
    );
}

test "Memory: countAccessedAddressesInSegment should return null if segment does not exist in data" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    try expectEqual(
        @as(?usize, null),
        memory.countAccessedAddressesInSegment(8),
    );
}

test "Memory: countAccessedAddressesInSegment should return 0 if no accessed addresses" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 10, 1 }, .{3} },
            .{ .{ 10, 2 }, .{3} },
            .{ .{ 10, 3 }, .{3} },
            .{ .{ 10, 4 }, .{3} },
            .{ .{ 10, 5 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectEqual(
        @as(?usize, 0),
        memory.countAccessedAddressesInSegment(10),
    );
}

test "Memory: countAccessedAddressesInSegment should return number of accessed addresses" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 10, 1 }, .{3} },
            .{ .{ 10, 2 }, .{3} },
            .{ .{ 10, 3 }, .{3} },
            .{ .{ 10, 4 }, .{3} },
            .{ .{ 10, 5 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    memory.data.items[10].items[3].?.is_accessed = true;
    memory.data.items[10].items[4].?.is_accessed = true;
    memory.data.items[10].items[5].?.is_accessed = true;

    // Test checks
    try expectEqual(
        @as(?usize, 3),
        memory.countAccessedAddressesInSegment(10),
    );
}

test "AddressSet: contains should return false if segment index is negative" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    // Test checks
    try expect(!addressSet.contains(Relocatable.new(-10, 2)));
}

test "AddressSet: contains should return false if address key does not exist" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    // Test checks
    try expect(!addressSet.contains(Relocatable.new(10, 2)));
}

test "AddressSet: contains should return true if address key is true in address set" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();
    try addressSet.set.put(Relocatable.new(10, 2), true);

    // Test checks
    try expect(addressSet.contains(Relocatable.new(10, 2)));
}

test "AddressSet: addAddresses should add new addresses to the address set without negative indexes" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    const addresses: [4]Relocatable = .{
        Relocatable.new(0, 10),
        Relocatable.new(3, 4),
        Relocatable.new(-2, 2),
        Relocatable.new(23, 7),
    };

    _ = try addressSet.addAddresses(&addresses);

    // Test checks
    try expectEqual(@as(u32, 3), addressSet.set.count());
    try expect(addressSet.set.get(Relocatable.new(0, 10)).?);
    try expect(addressSet.set.get(Relocatable.new(3, 4)).?);
    try expect(addressSet.set.get(Relocatable.new(23, 7)).?);
}

test "AddressSet: len should return the number of addresses in the address set" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    const addresses: [4]Relocatable = .{
        Relocatable.new(0, 10),
        Relocatable.new(3, 4),
        Relocatable.new(-2, 2),
        Relocatable.new(23, 7),
    };

    _ = try addressSet.addAddresses(&addresses);

    // Test checks
    try expectEqual(@as(u32, 3), addressSet.len());
}

test "Memory: set should not rewrite memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});
    memory.num_segments += 1;
    try memory.set(
        std.testing.allocator,
        Relocatable.new(0, 1),
        .{ .felt = Felt252.fromInteger(23) },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(MemoryError.DuplicatedRelocation, memory.set(
        std.testing.allocator,
        Relocatable.new(0, 1),
        .{ .felt = Felt252.fromInteger(8) },
    ));
}
