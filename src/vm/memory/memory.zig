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
const MathError = @import("../error.zig").MathError;
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

    /// Checks equality between two MemoryCell instances.
    ///
    /// Checks whether two MemoryCell instances are equal based on their relocation information
    /// and accessed status.
    ///
    /// # Arguments
    ///
    /// - `other`: The other MemoryCell to compare against.
    ///
    /// # Returns
    ///
    /// Returns `true` if both MemoryCell instances are equal, otherwise `false`.
    pub fn eql(self: Self, other: Self) bool {
        return self.maybe_relocatable.eq(other.maybe_relocatable) and self.is_accessed == other.is_accessed;
    }

    /// Checks equality between slices of MemoryCell instances.
    ///
    /// Compares two slices of MemoryCell instances for equality based on their relocation information
    /// and accessed status.
    ///
    /// # Arguments
    ///
    /// - `a`: The first slice of MemoryCell instances to compare.
    /// - `b`: The second slice of MemoryCell instances to compare.
    ///
    /// # Returns
    ///
    /// Returns `true` if both slices of MemoryCell instances are equal, otherwise `false`.
    pub fn eqlSlice(a: []const ?Self, b: []const ?Self) bool {
        if (a.len != b.len) return false;
        if (a.ptr == b.ptr) return true;
        for (a, b) |a_elem, b_elem| {
            if (a_elem) |ann| {
                if (b_elem) |bnn| {
                    if (!ann.eql(bnn)) return false;
                } else {
                    return false;
                }
            }
            if (b_elem) |bnn| {
                if (a_elem) |ann| {
                    if (!ann.eql(bnn)) return false;
                } else {
                    return false;
                }
            }
        }
        return true;
    }

    /// Compares two MemoryCell instances based on their relocation information
    /// and accessed status, returning their order relationship.
    ///
    /// This function compares MemoryCell instances by their relocation information first.
    /// If the relocation information is the same, it considers their accessed status,
    /// favoring cells that have been accessed (.eq). It returns the order relationship
    /// between the MemoryCell instances: `.lt` for less than, `.gt` for greater than,
    /// and `.eq` for equal.
    ///
    /// # Arguments
    ///
    /// - `self`: The first MemoryCell instance to compare.
    /// - `other`: The second MemoryCell instance to compare against.
    ///
    /// # Returns
    ///
    /// Returns a `std.math.Order` representing the order relationship between
    /// the two MemoryCell instances.
    pub fn cmp(self: ?Self, other: ?Self) std.math.Order {
        if (self) |lhs| {
            if (other) |rhs| {
                return switch (lhs.maybe_relocatable.cmp(rhs.maybe_relocatable)) {
                    .eq => switch (lhs.is_accessed) {
                        true => if (rhs.is_accessed) .eq else .gt,
                        false => if (rhs.is_accessed) .lt else .eq,
                    },
                    else => |res| res,
                };
            }
            return .gt;
        }
        return if (other == null) .eq else .lt;
    }

    /// Compares two slices of MemoryCell instances for order relationship.
    ///
    /// This function compares two slices of MemoryCell instances based on their
    /// relocation information and accessed status, returning their order relationship.
    /// It iterates through the slices, comparing each corresponding pair of cells.
    /// If a difference in relocation information is found, it returns the order relationship
    /// between those cells. If one slice ends before the other, it returns `.lt` or `.gt`
    /// accordingly. If both slices are identical, it returns `.eq`.
    ///
    /// # Arguments
    ///
    /// - `a`: The first slice of MemoryCell instances to compare.
    /// - `b`: The second slice of MemoryCell instances to compare.
    ///
    /// # Returns
    ///
    /// Returns a `std.math.Order` representing the order relationship between
    /// the two slices of MemoryCell instances.
    pub fn cmpSlice(a: []const ?Self, b: []const ?Self) std.math.Order {
        if (a.ptr == b.ptr) return .eq;

        const len = @min(a.len, b.len);

        for (0..len) |i| {
            if (a[i]) |a_elem| {
                if (b[i]) |b_elem| {
                    const comp = a_elem.cmp(b_elem);
                    if (comp != .eq) return comp;
                } else {
                    return .gt;
                }
            }

            if (b[i]) |b_elem| {
                if (a[i]) |a_elem| {
                    const comp = a_elem.cmp(b_elem);
                    if (comp != .eq) return comp;
                } else {
                    return .lt;
                }
            }
        }

        if (a.len == b.len) return .eq;

        return if (len == a.len) .lt else .gt;
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

    /// Marks a `MemoryCell` as accessed at the specified relocatable address.
    /// # Arguments
    /// - `address` - The relocatable address to mark.
    pub fn markAsAccessed(self: *Self, address: Relocatable) void {
        const segment_index: usize = @intCast(if (address.segment_index < 0) -(address.segment_index + 1) else address.segment_index);
        (if (address.segment_index < 0) &self.temp_data else &self.data).items[segment_index].items[address.offset].?.markAccessed();
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

    /// Retrieves a segment of MemoryCell items at the specified index.
    ///
    /// Retrieves the segment of MemoryCell items located at the given index.
    ///
    /// # Arguments
    ///
    /// - `idx`: The index of the segment to retrieve.
    ///
    /// # Returns
    ///
    /// Returns the segment of MemoryCell items if it exists, or `null` if not found.
    fn getSegmentAtIndex(self: *Self, idx: i64) ?[]?MemoryCell {
        return switch (idx < 0) {
            true => blk: {
                const i: usize = @intCast(-(idx + 1));
                if (i < self.temp_data.items.len) {
                    break :blk self.temp_data.items[i].items;
                } else {
                    break :blk null;
                }
            },
            false => if (idx < self.data.items.len) self.data.items[@intCast(idx)].items else null,
        };
    }

    /// Compares two memory segments within the VM's memory starting from specified addresses
    /// for a given length.
    ///
    /// This function provides a comparison mechanism for memory segments within the VM's memory.
    /// It compares the segments starting from the specified `lhs` (left-hand side) and `rhs`
    /// (right-hand side) addresses for a length defined by `len`.
    ///
    /// Special Cases:
    /// - If `lhs` exists in memory but `rhs` does not: returns `(Order::Greater, 0)`.
    /// - If `rhs` exists in memory but `lhs` does not: returns `(Order::Less, 0)`.
    /// - If neither `lhs` nor `rhs` exist in memory: returns `(Order::Equal, 0)`.
    ///
    /// The function behavior aligns with the C `memcmp` function for other cases,
    /// offering an optimized comparison mechanism that hints to avoid unnecessary allocations.
    ///
    /// # Arguments
    ///
    /// - `lhs`: The starting address of the left-hand memory segment.
    /// - `rhs`: The starting address of the right-hand memory segment.
    /// - `len`: The length to compare from each memory segment.
    ///
    /// # Returns
    ///
    /// Returns a tuple containing the ordering of the segments and the first relative position
    /// where they differ.
    pub fn memCmp(
        self: *Self,
        lhs: Relocatable,
        rhs: Relocatable,
        len: usize,
    ) std.meta.Tuple(&.{ std.math.Order, usize }) {
        const r = self.getSegmentAtIndex(rhs.segment_index);
        if (self.getSegmentAtIndex(lhs.segment_index)) |ls| {
            if (r) |rs| {
                for (0..len) |i| {
                    const l_idx: usize = @intCast(lhs.offset + i);
                    const r_idx: usize = @intCast(rhs.offset + i);
                    return switch (MemoryCell.cmp(
                        if (l_idx < ls.len) ls[l_idx] else null,
                        if (r_idx < rs.len) rs[r_idx] else null,
                    )) {
                        .eq => continue,
                        else => |res| .{ res, i },
                    };
                }
            } else {
                return .{ .gt, 0 };
            }
        } else {
            return .{ if (r == null) .eq else .lt, 0 };
        }
        return .{ .eq, len };
    }

    /// Compares memory segments for equality.
    ///
    /// Compares segments of MemoryCell items starting from the specified addresses
    /// (`lhs` and `rhs`) for a given length.
    ///
    /// # Arguments
    ///
    /// - `lhs`: The starting address of the left-hand segment.
    /// - `rhs`: The starting address of the right-hand segment.
    /// - `len`: The length to compare from each segment.
    ///
    /// # Returns
    ///
    /// Returns `true` if segments are equal up to the specified length, otherwise `false`.
    pub fn memEq(self: *Self, lhs: Relocatable, rhs: Relocatable, len: usize) !bool {
        if (lhs.eq(rhs)) return true;

        const l = if (self.getSegmentAtIndex(lhs.segment_index)) |s| blk: {
            break :blk if (lhs.offset < s.len) s[lhs.offset..] else null;
        } else null;

        const r = if (self.getSegmentAtIndex(rhs.segment_index)) |s| blk: {
            break :blk if (rhs.offset < s.len) s[rhs.offset..] else null;
        } else null;

        if (l) |ls| {
            if (r) |rs| {
                const lhs_len = @min(ls.len, len);
                const rhs_len = @min(rs.len, len);

                return switch (lhs_len == rhs_len) {
                    true => MemoryCell.eqlSlice(ls[0..lhs_len], rs[0..rhs_len]),
                    else => false,
                };
            }
            return false;
        }
        return r == null;
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

    /// Retrieves a continuous range of memory values starting from a specified address.
    ///
    /// # Arguments
    ///
    /// * `allocator`: The allocator used for the memory allocation of the returned list.
    /// * `address`: The starting address in the memory from which the continuous range is retrieved.
    /// * `size`: The size of the continuous range to be retrieved.
    ///
    /// # Returns
    ///
    /// Returns a list containing memory values retrieved from the continuous range starting at the given address.
    ///
    /// # Errors
    ///
    /// Returns an error if there are any gaps encountered within the continuous memory range.
    pub fn getContinuousRange(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        size: usize,
    ) !std.ArrayList(MaybeRelocatable) {
        var values = try std.ArrayList(MaybeRelocatable).initCapacity(
            allocator,
            size,
        );
        errdefer values.deinit();
        for (0..size) |i| {
            if (try self.get(try address.addUint(@intCast(i)))) |elem| {
                try values.append(elem);
            } else {
                return MemoryError.GetRangeMemoryGap;
            }
        }
        return values;
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

test "Memory: memEq should return true if lhs and rhs are the same" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try expect(try memory.memEq(
        Relocatable.new(2, 3),
        Relocatable.new(2, 3),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs segments don't exist in memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try expect(try memory.memEq(
        Relocatable.new(2, 3),
        Relocatable.new(2, 10),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs segments don't exist in memory with negative indexes" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try expect(try memory.memEq(
        Relocatable.new(-2, 3),
        Relocatable.new(-2, 10),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs offset are out of bounds for the given segments" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(try memory.memEq(
        Relocatable.new(0, 9),
        Relocatable.new(1, 11),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs offset are out of bounds for the given segments with negative indexes" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ -2, 7 }, .{3} },
            .{ .{ -4, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(try memory.memEq(
        Relocatable.new(-2, 9),
        Relocatable.new(-4, 11),
        10,
    ));
}

test "Memory: memEq should return false if lhs offset is out of bounds for the given segment but not rhs" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.new(0, 9),
        Relocatable.new(1, 5),
        10,
    )));
}

test "Memory: memEq should return false if rhs offset is out of bounds for the given segment but not lhs" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.new(0, 5),
        Relocatable.new(1, 20),
        10,
    )));
}

test "Memory: memEq should return false if lhs offset is out of bounds for the given segment but not rhs (negative indexes)" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ -1, 7 }, .{3} },
            .{ .{ -3, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.new(-1, 9),
        Relocatable.new(-3, 5),
        10,
    )));
}

test "Memory: memEq should return false if rhs offset is out of bounds for the given segment but not lhs (negative indexes)" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ -1, 7 }, .{3} },
            .{ .{ -3, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.new(-1, 5),
        Relocatable.new(-3, 20),
        10,
    )));
}

test "Memory: memEq should return false if lhs and rhs segment size after offset is not the same " {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.new(0, 5),
        Relocatable.new(1, 5),
        10,
    )));
}

test "Memory: memEq should return true if lhs and rhs segment are the same after offset" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(try memory.memEq(
        Relocatable.new(0, 5),
        Relocatable.new(1, 8),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs segment are the same after cut by len" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 0, 15 }, .{33} },
            .{ .{ 1, 7 }, .{3} },
            .{ .{ 1, 15 }, .{44} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect((try memory.memEq(
        Relocatable.new(0, 5),
        Relocatable.new(1, 5),
        4,
    )));
}

test "Memory: memCmp function" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try setUpMemory(
        memory,
        std.testing.allocator,
        .{
            .{ .{ -2, 0 }, .{1} },
            .{ .{ -2, 1 }, .{ 1, 1 } },
            .{ .{ -2, 3 }, .{0} },
            .{ .{ -2, 4 }, .{0} },
            .{ .{ -1, 0 }, .{1} },
            .{ .{ -1, 1 }, .{ 1, 1 } },
            .{ .{ -1, 3 }, .{0} },
            .{ .{ -1, 4 }, .{3} },
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ 1, 1 } },
            .{ .{ 0, 3 }, .{0} },
            .{ .{ 0, 4 }, .{0} },
            .{ .{ 1, 0 }, .{1} },
            .{ .{ 1, 1 }, .{ 1, 1 } },
            .{ .{ 1, 3 }, .{0} },
            .{ .{ 1, 4 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 3 }),
        memory.memCmp(
            Relocatable.new(0, 0),
            Relocatable.new(0, 0),
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 3 }),
        memory.memCmp(
            Relocatable.new(0, 0),
            Relocatable.new(1, 0),
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 4 }),
        memory.memCmp(
            Relocatable.new(0, 0),
            Relocatable.new(1, 0),
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 4 }),
        memory.memCmp(
            Relocatable.new(1, 0),
            Relocatable.new(0, 0),
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 0 }),
        memory.memCmp(
            Relocatable.new(2, 2),
            Relocatable.new(2, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 0 }),
        memory.memCmp(
            Relocatable.new(0, 0),
            Relocatable.new(2, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 0 }),
        memory.memCmp(
            Relocatable.new(2, 5),
            Relocatable.new(0, 0),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 3 }),
        memory.memCmp(
            Relocatable.new(-2, 0),
            Relocatable.new(-2, 0),
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 3 }),
        memory.memCmp(
            Relocatable.new(-2, 0),
            Relocatable.new(-1, 0),
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 4 }),
        memory.memCmp(
            Relocatable.new(-2, 0),
            Relocatable.new(-1, 0),
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 4 }),
        memory.memCmp(
            Relocatable.new(-1, 0),
            Relocatable.new(-2, 0),
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 0 }),
        memory.memCmp(
            Relocatable.new(-3, 2),
            Relocatable.new(-3, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 0 }),
        memory.memCmp(
            Relocatable.new(-2, 0),
            Relocatable.new(-3, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 0 }),
        memory.memCmp(
            Relocatable.new(-3, 5),
            Relocatable.new(-2, 0),
            8,
        ),
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

test "Memory: getContinuousRange for continuous memory" {
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

    var expected_vec = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer expected_vec.deinit();

    try expected_vec.append(MaybeRelocatable.fromU256(2));
    try expected_vec.append(MaybeRelocatable.fromU256(3));
    try expected_vec.append(MaybeRelocatable.fromU256(4));

    var actual = try memory.getContinuousRange(
        std.testing.allocator,
        Relocatable.new(1, 0),
        3,
    );
    defer actual.deinit();

    // Test checks
    try expectEqualSlices(
        MaybeRelocatable,
        expected_vec.items,
        actual.items,
    );
}

test "Memory: getContinuousRange for non continuous memory" {
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

    // Test checks
    try expectError(
        MemoryError.GetRangeMemoryGap,
        memory.getContinuousRange(
            std.testing.allocator,
            Relocatable.new(1, 0),
            3,
        ),
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

test "MemoryCell: eql function" {
    // Test setup
    const memoryCell1 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    const memoryCell2 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    const memoryCell3 = MemoryCell.new(.{ .felt = Felt252.fromInteger(3) });
    var memoryCell4 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    memoryCell4.is_accessed = true;

    // Test checks
    try expect(memoryCell1.eql(memoryCell2));
    try expect(!memoryCell1.eql(memoryCell3));
    try expect(!memoryCell1.eql(memoryCell4));
}

test "MemoryCell: eqlSlice should return false if slice len are not the same" {
    // Test setup
    const memoryCell1 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    const memoryCell2 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    const memoryCell3 = MemoryCell.new(.{ .felt = Felt252.fromInteger(3) });

    // Test checks
    try expect(!MemoryCell.eqlSlice(
        &[_]?MemoryCell{ memoryCell1, memoryCell2 },
        &[_]?MemoryCell{ memoryCell1, memoryCell2, memoryCell3 },
    ));
}

test "MemoryCell: eqlSlice should return true if same pointer" {
    // Test setup
    const memoryCell1 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    const memoryCell2 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });

    const a = [_]?MemoryCell{ memoryCell1, memoryCell2 };

    // Test checks
    try expect(MemoryCell.eqlSlice(&a, &a));
}

test "MemoryCell: eqlSlice should return false if slice are not equal" {
    // Test setup
    const memoryCell1 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    const memoryCell2 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });

    // Test checks
    try expect(!MemoryCell.eqlSlice(
        &[_]?MemoryCell{ memoryCell1, memoryCell2 },
        &[_]?MemoryCell{ null, memoryCell2 },
    ));
}

test "MemoryCell: eqlSlice should return true if slice are equal" {
    // Test setup
    const memoryCell1 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });
    const memoryCell2 = MemoryCell.new(.{ .felt = Felt252.fromInteger(10) });

    // Test checks
    try expect(MemoryCell.eqlSlice(
        &[_]?MemoryCell{ null, memoryCell1, null, memoryCell2, null },
        &[_]?MemoryCell{ null, memoryCell1, null, memoryCell2, null },
    ));
    try expect(MemoryCell.eqlSlice(
        &[_]?MemoryCell{ memoryCell1, memoryCell2 },
        &[_]?MemoryCell{ memoryCell1, memoryCell2 },
    ));
    try expect(MemoryCell.eqlSlice(
        &[_]?MemoryCell{ null, null, null },
        &[_]?MemoryCell{ null, null, null },
    ));
}

test "MemoryCell: cmp should compare two Relocatable Memory cell instance" {
    // Testing if two MemoryCell instances with the same relocatable segment and offset
    // should return an equal comparison.
    try expectEqual(
        std.math.Order.eq,
        MemoryCell.new(MaybeRelocatable.fromSegment(4, 10)).cmp(MemoryCell.new(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with is_accessed set to true and another MemoryCell
    // with the same relocatable segment and offset but is_accessed set to false should result in a less than comparison.
    var memCell = MemoryCell.new(MaybeRelocatable.fromSegment(4, 10));
    memCell.is_accessed = true;
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.new(MaybeRelocatable.fromSegment(4, 10)).cmp(memCell),
    );

    // Testing the opposite of the previous case where is_accessed is set to false for the first MemoryCell,
    // and true for the second MemoryCell with the same relocatable segment and offset. It should result in a greater than comparison.
    try expectEqual(
        std.math.Order.gt,
        memCell.cmp(MemoryCell.new(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a smaller offset compared to another MemoryCell instance
    // with the same segment but a larger offset should result in a less than comparison.
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.new(MaybeRelocatable.fromSegment(4, 5)).cmp(MemoryCell.new(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a larger offset compared to another MemoryCell instance
    // with the same segment but a smaller offset should result in a greater than comparison.
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.new(MaybeRelocatable.fromSegment(4, 15)).cmp(MemoryCell.new(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a smaller segment index compared to another MemoryCell instance
    // with a larger segment index but the same offset should result in a less than comparison.
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.new(MaybeRelocatable.fromSegment(2, 15)).cmp(MemoryCell.new(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a larger segment index compared to another MemoryCell instance
    // with a smaller segment index but the same offset should result in a greater than comparison.
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.new(MaybeRelocatable.fromSegment(20, 15)).cmp(MemoryCell.new(MaybeRelocatable.fromSegment(4, 10))),
    );
}

test "MemoryCell: cmp should return an error if incompatible types for a comparison" {
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.new(MaybeRelocatable.fromSegment(
            4,
            10,
        )).cmp(MemoryCell.new(MaybeRelocatable.fromU256(4))),
    );
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.new(MaybeRelocatable.fromU256(
            4,
        )).cmp(MemoryCell.new(MaybeRelocatable.fromSegment(4, 10))),
    );
}

test "MemoryCell: cmp should return proper order results for Felt252 comparisons" {
    // Should return less than (lt) when the first Felt252 is smaller than the second Felt252.
    try expectEqual(std.math.Order.lt, MemoryCell.new(MaybeRelocatable.fromU256(10)).cmp(MemoryCell.new(MaybeRelocatable.fromU256(343535))));

    // Should return greater than (gt) when the first Felt252 is larger than the second Felt252.
    try expectEqual(std.math.Order.gt, MemoryCell.new(MaybeRelocatable.fromU256(543636535)).cmp(MemoryCell.new(MaybeRelocatable.fromU256(434))));

    // Should return equal (eq) when both Felt252 values are identical.
    try expectEqual(std.math.Order.eq, MemoryCell.new(MaybeRelocatable.fromU256(10)).cmp(MemoryCell.new(MaybeRelocatable.fromU256(10))));

    // Should return less than (lt) when the cell's accessed status differs.
    var memCell = MemoryCell.new(MaybeRelocatable.fromU256(10));
    memCell.is_accessed = true;
    try expectEqual(std.math.Order.lt, MemoryCell.new(MaybeRelocatable.fromU256(10)).cmp(memCell));

    // Should return greater than (gt) when the cell's accessed status differs (reversed order).
    try expectEqual(std.math.Order.gt, memCell.cmp(MemoryCell.new(MaybeRelocatable.fromU256(10))));
}

test "MemoryCell: cmp with null values" {
    const memCell = MemoryCell.new(MaybeRelocatable.fromSegment(4, 15));
    const memCell1 = MemoryCell.new(MaybeRelocatable.fromU256(15));

    try expectEqual(std.math.Order.lt, MemoryCell.cmp(null, memCell));
    try expectEqual(std.math.Order.gt, MemoryCell.cmp(memCell, null));
    try expectEqual(std.math.Order.lt, MemoryCell.cmp(null, memCell1));
    try expectEqual(std.math.Order.gt, MemoryCell.cmp(memCell1, null));
}

test "MemoryCell: cmpSlice should compare MemoryCell slices (if eq and one longer than the other)" {
    const memCell = MemoryCell.new(MaybeRelocatable.fromSegment(4, 15));

    try expectEqual(
        std.math.Order.gt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ null, null, memCell, memCell },
            &[_]?MemoryCell{ null, null, memCell },
        ),
    );

    try expectEqual(
        std.math.Order.lt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ null, null, memCell },
            &[_]?MemoryCell{ null, null, memCell, memCell },
        ),
    );
}

test "MemoryCell: cmpSlice should return .eq if both slices are equal" {
    const memCell = MemoryCell.new(MaybeRelocatable.fromSegment(4, 15));
    const memCell1 = MemoryCell.new(MaybeRelocatable.fromU256(15));
    const slc = &[_]?MemoryCell{ null, null, memCell };

    try expectEqual(
        std.math.Order.eq,
        MemoryCell.cmpSlice(slc, slc),
    );
    try expectEqual(
        std.math.Order.eq,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell, null },
            &[_]?MemoryCell{ memCell1, null, memCell, null },
        ),
    );
    try expectEqual(
        std.math.Order.eq,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell, null },
            &[_]?MemoryCell{ memCell1, null, memCell, null },
        ),
    );
}

test "MemoryCell: cmpSlice should return .lt if a < b" {
    const memCell = MemoryCell.new(MaybeRelocatable.fromSegment(40, 15));
    const memCell1 = MemoryCell.new(MaybeRelocatable.fromSegment(3, 15));
    const memCell2 = MemoryCell.new(MaybeRelocatable.fromU256(10));
    const memCell3 = MemoryCell.new(MaybeRelocatable.fromU256(15));

    try expectEqual(
        std.math.Order.lt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell1, null },
            &[_]?MemoryCell{ memCell1, null, memCell, null },
        ),
    );
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell2, null },
            &[_]?MemoryCell{ memCell1, null, memCell3, null },
        ),
    );
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell, null },
            &[_]?MemoryCell{ memCell1, null, memCell3, null },
        ),
    );
}

test "MemoryCell: cmpSlice should return .gt if a > b" {
    const memCell = MemoryCell.new(MaybeRelocatable.fromSegment(40, 15));
    const memCell1 = MemoryCell.new(MaybeRelocatable.fromSegment(3, 15));
    const memCell2 = MemoryCell.new(MaybeRelocatable.fromU256(10));
    const memCell3 = MemoryCell.new(MaybeRelocatable.fromU256(15));

    try expectEqual(
        std.math.Order.gt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell, null },
            &[_]?MemoryCell{ memCell1, null, memCell1, null },
        ),
    );
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell3, null },
            &[_]?MemoryCell{ memCell1, null, memCell2, null },
        ),
    );
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.cmpSlice(
            &[_]?MemoryCell{ memCell1, null, memCell3, null },
            &[_]?MemoryCell{ memCell1, null, memCell, null },
        ),
    );
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
