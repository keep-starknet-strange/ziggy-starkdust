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
pub const validation_rule = *const fn (Allocator, *Memory, Relocatable) anyerror!std.ArrayList(Relocatable);

pub const MemoryCell = struct {
    /// Represents a memory cell that holds relocation information and access status.
    const Self = @This();
    /// The index or relocation information of the memory segment.
    maybe_relocatable: MaybeRelocatable,
    /// Indicates whether the MemoryCell has been accessed.
    is_accessed: bool = false,

    /// Creates a new MemoryCell.
    ///
    /// # Arguments
    /// - `maybe_relocatable`: The index or relocation information of the memory segment.
    /// # Returns
    /// A new MemoryCell.
    pub fn init(maybe_relocatable: MaybeRelocatable) Self {
        return .{ .maybe_relocatable = maybe_relocatable };
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
    set: std.AutoHashMap(Relocatable, bool),

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
            if (address.segment_index >= 0)
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
    num_segments: u32 = 0,
    /// Number of temporary segments in the memory.
    num_temp_segments: u32 = 0,
    /// Hash map tracking validated addresses to ensure they have been properly validated.
    /// Consideration: Possible merge with `data` for optimization; benchmarking recommended.
    validated_addresses: AddressSet,
    /// Hash map linking temporary data indices to their corresponding relocation rules.
    /// Keys are derived from temp_data's indices (segment_index), starting at zero.
    /// For example, segment_index = -1 maps to key 0, -2 to key 1, and so on.
    relocation_rules: std.AutoHashMap(u64, Relocatable),
    /// Hash map associating segment indices with their respective validation rules.
    validation_rules: std.AutoHashMap(u32, validation_rule),

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

        memory.* = .{
            .allocator = allocator,
            .data = std.ArrayList(std.ArrayListUnmanaged(?MemoryCell)).init(allocator),
            .temp_data = std.ArrayList(std.ArrayListUnmanaged(?MemoryCell)).init(allocator),
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

    /// Retrieves data from the specified segment index.
    ///
    /// This function returns a reference to either the main data or temporary data based on the
    /// provided `segment_index`. If the `segment_index` is less than 0, the temporary data is
    /// returned; otherwise, the main data is returned.
    ///
    /// # Arguments
    ///
    /// - `segment_index`: The index of the segment for which data is to be retrieved.
    ///
    /// # Returns
    ///
    /// Returns a reference to the data in the form of `std.ArrayList(std.ArrayListUnmanaged(?MemoryCell))`.
    pub fn getDataFromSegmentIndex(
        self: *Self,
        segment_index: i64,
    ) *std.ArrayList(std.ArrayListUnmanaged(?MemoryCell)) {
        // Return the temporary data if the segment index is less than 0; otherwise, return the main data.
        return if (segment_index < 0) &self.temp_data else &self.data;
    }

    /// Memory management and insertion function for the Cairo Virtual Machine.
    /// This function inserts a value into the VM memory at the specified address.
    /// # Arguments
    /// - `allocator`: The allocator to use for memory operations.
    /// - `address`: The target address to insert the value.
    /// - `value`: The value to be inserted, possibly containing relocation information.
    /// # Returns
    /// - `void` on successful insertion.
    /// - `MemoryError.UnallocatedSegment` if the target segment is not allocated.
    /// - `MemoryError.DuplicatedRelocation` if there is an attempt to overwrite existing memory.
    /// # Safety
    /// This function assumes proper initialization and management of the VM memory.
    pub fn set(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        value: MaybeRelocatable,
    ) !void {
        // Retrieve the appropriate data segment based on the segment index of the given address.
        var data = self.getDataFromSegmentIndex(address.segment_index);
        const insert_segment_index = address.getAdjustedSegmentIndex();

        // Check if the data segment is allocated for the given segment index.
        if (data.items.len <= insert_segment_index)
            return MemoryError.UnallocatedSegment;

        var data_segment = &data.items[insert_segment_index];

        // Ensure the data segment has sufficient capacity to accommodate the value at the specified offset.
        if (data_segment.items.len <= address.offset) {
            try data_segment.appendNTimes(
                allocator,
                null,
                address.offset + 1 - data_segment.items.len,
            );
        }

        // Check for existing memory at the specified address to avoid overwriting.
        if (data_segment.items[address.offset]) |item| {
            if (!item.maybe_relocatable.eq(value))
                return MemoryError.DuplicatedRelocation;
        }

        // Insert the value into the VM memory at the specified address.
        data_segment.items[address.offset] = MemoryCell.init(value);
    }

    /// Retrieves data at a specified address within a relocatable data structure.
    ///
    /// This function allows you to retrieve data from a relocatable data structure at a given address.
    /// The provided `address` is used to locate the data within the structure.
    ///
    /// # Arguments
    /// - `self`: The instance of the data structure.
    /// - `address`: The target address to retrieve data from.
    ///
    /// # Returns
    /// Returns a `MaybeRelocatable` value if the address is valid; otherwise, returns `null`.
    ///
    /// # Example
    /// ```
    /// const myDataStructure = // initialize your data structure here
    /// const targetAddress = // specify the target address
    /// const result = myDataStructure.get(targetAddress);
    /// // Handle the result accordingly
    /// ```
    pub fn get(self: *Self, address: Relocatable) ?MaybeRelocatable {
        // Retrieve the data corresponding to the segment index from the data structure.
        const data = self.getDataFromSegmentIndex(address.segment_index);

        // Adjust the segment index based on the target address.
        const segment_index = address.getAdjustedSegmentIndex();

        // Check if the segment index is valid within the data structure.
        const isSegmentIndexValid = address.segment_index < data.items.len;

        // Check if the offset is valid within the specified segment.
        const isOffsetValid = isSegmentIndexValid and (address.offset < data.items[segment_index].items.len);

        // Return null if either the segment index or offset is not valid.
        // Otherwise, return the maybe_relocatable value at the specified address.
        return if (!isSegmentIndexValid or !isOffsetValid)
            null
        else if (data.items[segment_index].items[address.offset]) |val|
            switch (val.maybe_relocatable) {
                .relocatable => |addr| Self.relocateAddress(addr, &self.relocation_rules) catch unreachable,
                else => |_| val.maybe_relocatable,
            }
        else
            null;
    }

    /// Retrieves a `Felt252` value from the memory at the specified relocatable address.
    ///
    /// This function internally calls `get` on the memory, attempting to retrieve a value at the given address.
    /// If the value is of type `Felt252`, it is returned; otherwise, an error of type `ExpectedInteger` is returned.
    /// If there is no value, an error of type 'UnknownMemoryCell' is returned.
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
    ) error{ ExpectedInteger, UnknownMemoryCell }!Felt252 {
        return if (self.get(address)) |m|
            switch (m) {
                .felt => |fe| fe,
                else => MemoryError.ExpectedInteger,
            }
        else
            MemoryError.UnknownMemoryCell;
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
    ) error{ExpectedRelocatable}!Relocatable {
        return if (self.get(address)) |m|
            switch (m) {
                .relocatable => |rel| rel,
                else => MemoryError.ExpectedRelocatable,
            }
        else
            MemoryError.ExpectedRelocatable;
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
        const segment_index = address.getAdjustedSegmentIndex();
        var data = self.getDataFromSegmentIndex(address.segment_index);

        if (segment_index < data.items.len) {
            if (address.offset < data.items[segment_index].items.len) {
                if (data.items[segment_index].items[address.offset]) |*memory_cell|
                    memory_cell.is_accessed = true;
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
        const segment_index = src_ptr.getAdjustedSegmentIndex();
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
                const list = try rule(self.allocator, self, address);
                defer list.deinit();
                try self.validated_addresses.addAddresses(list.items);
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
                if (cell) |_| {
                    try self.validateMemoryCell(Relocatable.init(
                        @intCast(i),
                        j,
                    ));
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
                break :blk if (i < self.temp_data.items.len)
                    self.temp_data.items[i].items
                else
                    null;
            },
            false => if (idx < self.data.items.len)
                self.data.items[@intCast(idx)].items
            else
                null,
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
                    const l_idx = lhs.offset + i;
                    const r_idx = rhs.offset + i;
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
        // Check if the left and right addresses are the same, in which case the segments are equal.
        if (lhs.eq(rhs)) return true;

        // Get the segment starting from the left-hand address.
        const l = if (self.getSegmentAtIndex(lhs.segment_index)) |s|
            // Check if the offset is within the bounds of the segment.
            if (lhs.offset < s.len) s[lhs.offset..] else null
        else
            null;

        // Get the segment starting from the right-hand address.
        const r = if (self.getSegmentAtIndex(rhs.segment_index)) |s|
            // Check if the offset is within the bounds of the segment.
            if (rhs.offset < s.len) s[rhs.offset..] else null
        else
            null;

        // If the left segment exists, perform further checks.
        if (l) |ls| {
            // If the right segment also exists, compare the segments up to the specified length.
            if (r) |rs| {
                // Determine the actual lengths to compare.
                const lhs_len = @min(ls.len, len);
                const rhs_len = @min(rs.len, len);

                // Compare slices of MemoryCell items up to the specified length.
                return switch (lhs_len == rhs_len) {
                    true => MemoryCell.eqlSlice(ls[0..lhs_len], rs[0..rhs_len]),
                    else => false,
                };
            }
            // If only the left segment exists, return false.
            return false;
        }

        // If the left segment does not exist, return true only if the right segment is also null.
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
        errdefer values.deinit();
        for (0..size) |i| {
            try values.append(self.get(try address.addUint(i)));
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
            if (self.get(try address.addUint(i))) |elem| {
                try values.append(elem);
            } else {
                return MemoryError.GetRangeMemoryGap;
            }
        }
        return values;
    }

    /// Retrieves a continuous range of `Felt252` values starting from a specified address.
    ///
    /// # Arguments
    ///
    /// * `address`: The starting address in the memory from which the continuous range of `Felt252` is retrieved.
    /// * `size`: The size of the continuous range of `Felt252` to be retrieved.
    ///
    /// # Returns
    ///
    /// Returns a list containing `Felt252` values retrieved from the continuous range starting at the given address.
    ///
    /// # Errors
    ///
    /// Returns an error if there are any unknown memory cell encountered within the continuous memory range.
    /// Returns an error if value inside the range is not a `Felt252`
    pub fn getFeltRange(
        self: *Self,
        address: Relocatable,
        size: usize,
    ) !std.ArrayList(Felt252) {
        var values = try std.ArrayList(Felt252).initCapacity(
            self.allocator,
            size,
        );
        errdefer values.deinit();
        for (0..size) |i| {
            try values.append(try self.getFelt(try address.addUint(i)));
        }
        return values;
    }

    /// Relocates a value represented as `Felt252`.
    ///
    /// This function relocates and returns the input `Felt252` value.
    ///
    /// # Arguments
    ///
    /// - `value`: The `Felt252` value to be relocated.
    ///
    /// # Returns
    ///
    /// Returns the input `Felt252` value.
    pub fn relocateValueFromFelt(_: *Self, value: Felt252) Felt252 {
        return value;
    }

    /// Relocates an address represented as `Relocatable` based on provided relocation rules.
    ///
    /// This function handles the relocation of a `Relocatable` address by verifying relocation rules
    /// and updating the address if necessary.
    ///
    /// # Arguments
    ///
    /// - `address`: The original `Relocatable` address to be relocated.
    /// - `relocation_rules`: A pointer to a hash map containing relocation rules.
    ///
    /// # Returns
    ///
    /// Returns a `MaybeRelocatable` value after applying relocation rules to the provided address.
    pub fn relocateAddress(
        address: Relocatable,
        relocation_rules: *std.AutoHashMap(u64, Relocatable),
    ) !MaybeRelocatable {
        // Check if the segment index of the provided address is already valid.
        if (address.segment_index >= 0) return MaybeRelocatable.fromRelocatable(address);

        // Attempt to retrieve relocation rules for the given segment index.
        return if (relocation_rules.get(address.getAdjustedSegmentIndex())) |x|
            // If rules exist, add the address offset according to the rules.
            MaybeRelocatable.fromRelocatable(try x.addUint(address.offset))
        else
            // If no rules exist, return the address without modification.
            MaybeRelocatable.fromRelocatable(address);
    }

    /// Relocates a value represented as `Relocatable`.
    ///
    /// This function handles the relocation of a `Relocatable` address by checking
    /// relocation rules and returning the updated `Relocatable` address if necessary.
    ///
    /// # Arguments
    ///
    /// - `address`: The `Relocatable` address to be relocated.
    ///
    /// # Returns
    ///
    /// Returns the updated `Relocatable` address based on relocation rules or the original address.
    pub fn relocateValueFromRelocatable(self: *Self, address: Relocatable) !Relocatable {
        // Check if the segment index of the provided address is already valid.
        if (address.segment_index >= 0) return address;

        // Try to retrieve relocation rules for the given segment index.
        return if (self.relocation_rules.get(address.getAdjustedSegmentIndex())) |x|
            // If rules exist, add the address offset according to the rules.
            try x.addUint(address.offset)
        else
            // If no rules exist, return the address without modification.
            address;
    }

    /// Relocates a value represented as `MaybeRelocatable`.
    ///
    /// This function handles the relocation of a `MaybeRelocatable` value by checking its type.
    /// If it's a `felt` value, it remains unchanged. If it's a `relocatable` value, it calls
    /// `relocateValueFromRelocatable` to handle the relocation.
    ///
    /// # Arguments
    ///
    /// - `value`: The `MaybeRelocatable` value to be relocated.
    ///
    /// # Returns
    ///
    /// Returns the relocated `MaybeRelocatable` value.
    pub fn relocateValueFromMaybeRelocatable(self: *Self, value: MaybeRelocatable) !MaybeRelocatable {
        return switch (value) {
            .felt => value,
            .relocatable => |r| .{ .relocatable = try self.relocateValueFromRelocatable(r) },
        };
    }

    /// Relocates a memory segment based on predefined rules.
    ///
    /// This function iterates through a memory segment, applying relocation rules to
    /// efficiently move data to its final destination. It updates the memory cell's
    /// relocatable address if needed.
    ///
    /// # Arguments
    /// - `segment`: The memory segment to be relocated.
    ///
    /// # Errors
    /// Returns an error if relocation of an address fails.
    pub fn relocateSegment(self: *Self, segment: *std.ArrayListUnmanaged(?MemoryCell)) !void {
        for (segment.items) |*memory_cell| {
            if (memory_cell.*) |*cell| {
                // Check if the memory cell contains a relocatable address.
                switch (cell.maybe_relocatable) {
                    .relocatable => |address| {
                        // Check if the address is temporary.
                        if (address.segment_index < 0)
                            // Relocate the address using predefined rules.
                            cell.*.maybe_relocatable = try Memory.relocateAddress(
                                address,
                                &self.relocation_rules,
                            );
                    },
                    else => {},
                }
            }
        }
    }

    /// Relocates memory segments based on relocation rules.
    ///
    /// This function iterates through temporary and permanent memory segments,
    /// applying relocation rules to efficiently move data to its final destination.
    /// It clears relocation rules once the relocation process is complete.
    ///
    /// # Errors
    /// Returns an error if memory allocation or relocation fails.
    pub fn relocateMemory(self: *Self) !void {
        // Check if relocation is necessary.
        if (self.relocation_rules.count() == 0 or self.temp_data.items.len == 0) {
            return;
        }

        // Relocate segments in the main data.
        for (self.data.items) |*segment|
            try self.relocateSegment(segment);

        // Relocate segments in temporary data.
        for (self.temp_data.items) |*segment|
            try self.relocateSegment(segment);

        // Iterate through relocation rules in reverse order.
        var index = self.temp_data.items.len;
        while (index > 0) {
            index -= 1;

            // Get the base address from relocation rules.
            if (self.relocation_rules.get(index)) |base_address| {
                // Remove the corresponding temporary data segment.
                var data_segment = self.temp_data.orderedRemove(index);
                defer data_segment.deinit(self.allocator);

                // Initialize the address for relocation.
                var address = base_address;

                // Ensure capacity in the destination segment.
                const idx_data: usize = @intCast(address.segment_index);
                if (idx_data < self.data.items.len)
                    try (self.data.items[idx_data]).ensureUnusedCapacity(
                        self.allocator,
                        data_segment.items.len,
                    );

                // Copy and relocate each cell from the temporary segment to the main data.
                for (data_segment.items) |cell| {
                    if (cell) |c| {
                        try self.set(
                            self.allocator,
                            address,
                            c.maybe_relocatable,
                        );
                    }

                    // Move to the next address.
                    address = try address.addUint(1);
                }
            }
        }

        // Clear and free relocation rules after relocation.
        self.relocation_rules.clearAndFree();
    }

    // Utility function to help set up memory for tests
    //
    // # Arguments
    // - `memory` - memory to be set
    // - `vals` - complile time structure with heterogenous types
    pub fn setUpMemory(self: *Self, allocator: Allocator, comptime vals: anytype) !void {
        const segment = std.ArrayListUnmanaged(?MemoryCell){};
        var si: usize = 0;
        inline for (vals) |row| {
            if (row[0][0] < 0) {
                si = @intCast(-(row[0][0] + 1));
                while (si >= self.num_temp_segments) {
                    try self.temp_data.append(segment);
                    self.num_temp_segments += 1;
                }
            } else {
                si = @intCast(row[0][0]);
                while (si >= self.num_segments) {
                    try self.data.append(segment);
                    self.num_segments += 1;
                }
            }
            // Check number of inputs in row
            if (row[1].len == 1) {
                try self.set(
                    allocator,
                    Relocatable.init(row[0][0], row[0][1]),
                    if (row[1][0] >= 0)
                        MaybeRelocatable.fromInt(u256, row[1][0])
                    else
                        MaybeRelocatable.fromFelt(Felt252.fromInt(u256, -row[1][0]).neg()),
                );
            } else {
                switch (@typeInfo(@TypeOf(row[1][0]))) {
                    .Pointer => {
                        try self.set(
                            allocator,
                            Relocatable.init(row[0][0], row[0][1]),
                            MaybeRelocatable.fromSegment(
                                try std.fmt.parseUnsigned(i64, row[1][0], 10),
                                row[1][1],
                            ),
                        );
                    },
                    else => {
                        try self.set(
                            allocator,
                            Relocatable.init(row[0][0], row[0][1]),
                            MaybeRelocatable.fromSegment(row[1][0], row[1][1]),
                        );
                    },
                }
            }
        }
    }
};

test "Memory: validate existing memory" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.init(8, 8, true);
    try builtin.initSegments(segments);
    try builtin.addValidationRule(segments.memory);

    try segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 2 }, .{1} },
        .{ .{ 0, 5 }, .{1} },
        .{ .{ 0, 7 }, .{1} },
        .{ .{ 1, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
    });
    defer segments.memory.deinitData(std.testing.allocator);

    try segments.memory.validateExistingMemory();

    try expect(
        segments.memory.validated_addresses.contains(Relocatable.init(0, 2)),
    );
    try expect(
        segments.memory.validated_addresses.contains(Relocatable.init(0, 5)),
    );
    try expect(
        segments.memory.validated_addresses.contains(Relocatable.init(0, 7)),
    );
    try expectEqual(
        false,
        segments.memory.validated_addresses.contains(Relocatable.init(1, 1)),
    );
    try expectEqual(
        false,
        segments.memory.validated_addresses.contains(Relocatable.init(2, 2)),
    );
}

test "Memory: validate memory cell" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.init(8, 8, true);
    try builtin.initSegments(segments);
    try builtin.addValidationRule(segments.memory);

    try segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 1 }, .{1} }},
    );

    try segments.memory.validateMemoryCell(Relocatable.init(0, 1));
    // null case
    defer segments.memory.deinitData(std.testing.allocator);

    try expectEqual(
        true,
        segments.memory.validated_addresses.contains(Relocatable.init(0, 1)),
    );
    try expectError(MemoryError.RangeCheckGetError, segments.memory.validateMemoryCell(Relocatable.init(0, 7)));
}

test "Memory: validate memory cell segment index not in validation rules" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.init(8, 8, true);
    try builtin.initSegments(segments);

    try segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 1 }, .{1} }},
    );

    try segments.memory.validateMemoryCell(Relocatable.init(0, 1));
    defer segments.memory.deinitData(std.testing.allocator);

    try expectEqual(
        segments.memory.validated_addresses.contains(Relocatable.init(0, 1)),
        false,
    );
}

test "Memory: validate memory cell already exist in validation rules" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    var builtin = RangeCheckBuiltinRunner.init(8, 8, true);
    try builtin.initSegments(segments);
    try builtin.addValidationRule(segments.memory);

    try segments.memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});
    const seg = segments.addSegment();
    _ = try seg;

    try segments.memory.set(std.testing.allocator, Relocatable.init(0, 1), MaybeRelocatable.fromFelt(starknet_felt.Felt252.one()));
    defer segments.memory.deinitData(std.testing.allocator);

    try segments.memory.validateMemoryCell(Relocatable.init(0, 1));

    try expectEqual(
        segments.memory.validated_addresses.contains(Relocatable.init(0, 1)),
        true,
    );

    //attempt to validate memory cell a second time
    try segments.memory.validateMemoryCell(Relocatable.init(0, 1));

    try expectEqual(
        segments.memory.validated_addresses.contains(Relocatable.init(0, 1)),
        // should stay true
        true,
    );
}

test "memory inner for testing test" {
    const allocator = std.testing.allocator;

    var memory = try Memory.init(allocator);
    defer memory.deinit();

    try memory.setUpMemory(
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
        Felt252.fromInt(u8, 23),
        try memory.getFelt(Relocatable.init(9, 10)),
    );

    try expectEqual(
        Relocatable.init(7, 8),
        try memory.getRelocatable(Relocatable.init(2, 6)),
    );

    try expectEqual(
        Relocatable.init(234, 10),
        try memory.getRelocatable(Relocatable.init(1, 2)),
    );
}

test "Memory: get method without segment should return null" {
    // Test setup
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    // Test checks
    // Get a value from the memory at an address that doesn't exist.
    try expectEqual(
        @as(?MaybeRelocatable, null),
        memory.get(.{}),
    );
}

test "Memory: get method wit segment but non allocated memory should return null" {
    // Test setup
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    // Set a value into the memory.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 10 }, .{1} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    // Get a value from the memory at an address that doesn't exist.
    try expectEqual(
        @as(?MaybeRelocatable, null),
        memory.get(Relocatable.init(0, 15)),
    );
}

test "Memory: set and get for both segments and temporary segments should return proper MaybeRelocatable values" {
    // Test setup
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    // Set a value into the memory.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ -1, 0 }, .{1} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectEqual(
        @as(?MaybeRelocatable, MaybeRelocatable.fromInt(u8, 1)),
        memory.get(.{}),
    );
    try expectEqual(
        @as(?MaybeRelocatable, MaybeRelocatable.fromInt(u8, 1)),
        memory.get(Relocatable.init(-1, 0)),
    );
}

test "Memory: get inside a segment without value but inbout should return null" {
    // Test setup
    // Initialize an allocator.
    const allocator = std.testing.allocator;

    // Initialize a memory instance.
    var memory = try Memory.init(allocator);
    defer memory.deinit();

    // Test body
    try memory.setUpMemory(
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
        memory.get(Relocatable.init(1, 3)),
    );
}

test "Memory: set where number of segments is less than segment index should return UnallocatedSegment error" {
    const allocator = std.testing.allocator;

    var segments = try MemorySegmentManager.init(allocator);
    defer segments.deinit();

    try segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 1 }, .{1} }},
    );

    try expectError(
        MemoryError.UnallocatedSegment,
        segments.memory.set(
            allocator,
            Relocatable.init(3, 1),
            .{ .felt = Felt252.three() },
        ),
    );
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

    var builtin = RangeCheckBuiltinRunner.init(8, 8, true);
    try builtin.initSegments(segments);

    // ************************************************************
    // *                      TEST BODY                           *
    // ************************************************************
    const address_1 = Relocatable.init(
        0,
        0,
    );
    const value_1 = MaybeRelocatable.fromFelt(starknet_felt.Felt252.one());

    // Set a value into the memory.
    try memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{1} }},
    );

    defer memory.deinitData(std.testing.allocator);

    // Get the value from the memory.
    const maybe_value_1 = memory.get(address_1);

    // ************************************************************
    // *                      TEST CHECKS                         *
    // ************************************************************
    // Assert that the value is the expected value.
    try expect(maybe_value_1.?.eq(value_1));
}

test "Memory: getFelt should return UnknownMemoryCell error if address is unknown" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    try expectError(
        MemoryError.UnknownMemoryCell,
        memory.getFelt(.{}),
    );
}

test "Memory: getFelt should return Felt252 if available at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{23} }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectEqual(
        Felt252.fromInt(u8, 23),
        try memory.getFelt(.{}),
    );
}

test "Memory: getFelt should return ExpectedInteger error if Relocatable instead of Felt at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{ 3, 7 } }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        MemoryError.ExpectedInteger,
        memory.getFelt(.{}),
    );
}

test "Memory: getFelt should return UnknownMemoryCell error if no value at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{3} },
            .{ .{ 0, 2 }, .{4} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        MemoryError.UnknownMemoryCell,
        memory.getFelt(Relocatable.init(0, 1)),
    );
}

test "Memory: getRelocatable should return ExpectedRelocatable error if no value at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test checks
    try expectError(
        error.ExpectedRelocatable,
        memory.getRelocatable(.{}),
    );
}

test "Memory: getRelocatable should return Relocatable if available at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{ 4, 34 } }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectEqual(
        Relocatable.init(4, 34),
        try memory.getRelocatable(.{}),
    );
}

test "Memory: getRelocatable should return ExpectedRelocatable error if Felt instead of Relocatable at the given address" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{3} }},
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        error.ExpectedRelocatable,
        memory.getRelocatable(.{}),
    );
}

test "Memory: markAsAccessed should mark memory cell" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    const relo = Relocatable.init(0, 3);

    try memory.setUpMemory(
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

    memory.markAsAccessed(Relocatable.init(10, 0));
}

test "Memory: markAsAccessed should not panic if non existing offset" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 1, 3 }, .{ 4, 5 } }},
    );
    defer memory.deinitData(std.testing.allocator);

    memory.markAsAccessed(Relocatable.init(1, 17));
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
            Relocatable.init(1, 3),
            Relocatable.init(4, 7),
        ),
    );
    // Check if source pointer segment index is zero
    try expectError(
        MemoryError.AddressNotInTemporarySegment,
        memory.addRelocationRule(
            Relocatable.init(0, 3),
            Relocatable.init(4, 7),
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
            Relocatable.init(-2, 3),
            Relocatable.init(4, 7),
        ),
    );
}

test "Memory: addRelocationRule should return an error if another relocation present at same index" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.relocation_rules.put(1, Relocatable.init(9, 77));

    // Test checks
    try expectError(
        MemoryError.DuplicatedRelocation,
        memory.addRelocationRule(
            Relocatable.init(-2, 0),
            Relocatable.init(4, 7),
        ),
    );
}

test "Memory: addRelocationRule should add new relocation rule" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    _ = try memory.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(4, 7),
    );

    // Test checks
    // Verify that relocation rule content is correct
    try expectEqual(
        @as(u32, 1),
        memory.relocation_rules.count(),
    );
    // Verify that new relocation rule was added properly
    try expectEqual(
        Relocatable.init(4, 7),
        memory.relocation_rules.get(1).?,
    );
}

test "Memory: memEq should return true if lhs and rhs are the same" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try expect(try memory.memEq(
        Relocatable.init(2, 3),
        Relocatable.init(2, 3),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs segments don't exist in memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try expect(try memory.memEq(
        Relocatable.init(2, 3),
        Relocatable.init(2, 10),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs segments don't exist in memory with negative indexes" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try expect(try memory.memEq(
        Relocatable.init(-2, 3),
        Relocatable.init(-2, 10),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs offset are out of bounds for the given segments" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(try memory.memEq(
        Relocatable.init(0, 9),
        Relocatable.init(1, 11),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs offset are out of bounds for the given segments with negative indexes" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ -2, 7 }, .{3} },
            .{ .{ -4, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(try memory.memEq(
        Relocatable.init(-2, 9),
        Relocatable.init(-4, 11),
        10,
    ));
}

test "Memory: memEq should return false if lhs offset is out of bounds for the given segment but not rhs" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.init(0, 9),
        Relocatable.init(1, 5),
        10,
    )));
}

test "Memory: memEq should return false if rhs offset is out of bounds for the given segment but not lhs" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.init(0, 5),
        Relocatable.init(1, 20),
        10,
    )));
}

test "Memory: memEq should return false if lhs offset is out of bounds for the given segment but not rhs (negative indexes)" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ -1, 7 }, .{3} },
            .{ .{ -3, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.init(-1, 9),
        Relocatable.init(-3, 5),
        10,
    )));
}

test "Memory: memEq should return false if rhs offset is out of bounds for the given segment but not lhs (negative indexes)" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ -1, 7 }, .{3} },
            .{ .{ -3, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.init(-1, 5),
        Relocatable.init(-3, 20),
        10,
    )));
}

test "Memory: memEq should return false if lhs and rhs segment size after offset is not the same " {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(!(try memory.memEq(
        Relocatable.init(0, 5),
        Relocatable.init(1, 5),
        10,
    )));
}

test "Memory: memEq should return true if lhs and rhs segment are the same after offset" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 7 }, .{3} },
            .{ .{ 1, 10 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    try expect(try memory.memEq(
        Relocatable.init(0, 5),
        Relocatable.init(1, 8),
        10,
    ));
}

test "Memory: memEq should return true if lhs and rhs segment are the same after cut by len" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
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
        Relocatable.init(0, 5),
        Relocatable.init(1, 5),
        4,
    )));
}

test "Memory: memCmp function" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
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
            .{},
            .{},
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 3 }),
        memory.memCmp(
            .{},
            Relocatable.init(1, 0),
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 4 }),
        memory.memCmp(
            .{},
            Relocatable.init(1, 0),
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 4 }),
        memory.memCmp(
            Relocatable.init(1, 0),
            .{},
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 0 }),
        memory.memCmp(
            Relocatable.init(2, 2),
            Relocatable.init(2, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 0 }),
        memory.memCmp(
            .{},
            Relocatable.init(2, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 0 }),
        memory.memCmp(
            Relocatable.init(2, 5),
            .{},
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 3 }),
        memory.memCmp(
            Relocatable.init(-2, 0),
            Relocatable.init(-2, 0),
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 3 }),
        memory.memCmp(
            Relocatable.init(-2, 0),
            Relocatable.init(-1, 0),
            3,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 4 }),
        memory.memCmp(
            Relocatable.init(-2, 0),
            Relocatable.init(-1, 0),
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 4 }),
        memory.memCmp(
            Relocatable.init(-1, 0),
            Relocatable.init(-2, 0),
            5,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .eq, 0 }),
        memory.memCmp(
            Relocatable.init(-3, 2),
            Relocatable.init(-3, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .gt, 0 }),
        memory.memCmp(
            Relocatable.init(-2, 0),
            Relocatable.init(-3, 5),
            8,
        ),
    );
    try expectEqual(
        @as(std.meta.Tuple(&.{ std.math.Order, usize }), .{ .lt, 0 }),
        memory.memCmp(
            Relocatable.init(-3, 5),
            Relocatable.init(-2, 0),
            8,
        ),
    );
}

test "Memory: getRange for continuous memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
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

    try expected_vec.append(MaybeRelocatable.fromInt(u8, 2));
    try expected_vec.append(MaybeRelocatable.fromInt(u8, 3));
    try expected_vec.append(MaybeRelocatable.fromInt(u8, 4));

    var actual = try memory.getRange(
        std.testing.allocator,
        Relocatable.init(1, 0),
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

    try memory.setUpMemory(
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

    try expected_vec.append(MaybeRelocatable.fromInt(u8, 2));
    try expected_vec.append(MaybeRelocatable.fromInt(u8, 3));
    try expected_vec.append(null);
    try expected_vec.append(MaybeRelocatable.fromInt(u8, 4));

    var actual = try memory.getRange(
        std.testing.allocator,
        Relocatable.init(1, 0),
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

    try memory.setUpMemory(
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

    try memory.setUpMemory(
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

    try memory.setUpMemory(
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

    try expected_vec.append(MaybeRelocatable.fromInt(u8, 2));
    try expected_vec.append(MaybeRelocatable.fromInt(u8, 3));
    try expected_vec.append(MaybeRelocatable.fromInt(u8, 4));

    var actual = try memory.getContinuousRange(
        std.testing.allocator,
        Relocatable.init(1, 0),
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

    try memory.setUpMemory(
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
            Relocatable.init(1, 0),
            3,
        ),
    );
}

test "Memory: getFeltRange for continuous memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{2} },
            .{ .{ 1, 1 }, .{3} },
            .{ .{ 1, 2 }, .{4} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    var expected_vec = std.ArrayList(Felt252).init(std.testing.allocator);
    defer expected_vec.deinit();

    try expected_vec.append(Felt252.two());
    try expected_vec.append(Felt252.three());
    try expected_vec.append(Felt252.fromInt(u8, 4));

    var actual = try memory.getFeltRange(
        Relocatable.init(1, 0),
        3,
    );
    defer actual.deinit();

    // Test checks
    try expectEqualSlices(
        Felt252,
        expected_vec.items,
        actual.items,
    );
}

test "Memory: getFeltRange for Relocatable instead of Felt" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{2} },
            .{ .{ 1, 1 }, .{ 3, 4 } },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        MemoryError.ExpectedInteger,
        memory.getFeltRange(
            Relocatable.init(1, 0),
            2,
        ),
    );
}

test "Memory: getFeltRange for out of bounds memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{2} },
            .{ .{ 1, 1 }, .{3} },
        },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(
        error.UnknownMemoryCell,
        memory.getFeltRange(
            Relocatable.init(1, 0),
            4,
        ),
    );
}

test "Memory: getFeltRange for non continuous memory" {
    // Test setup
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.setUpMemory(
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
        MemoryError.UnknownMemoryCell,
        memory.getFeltRange(
            Relocatable.init(1, 0),
            3,
        ),
    );
}

test "AddressSet: contains should return false if segment index is negative" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    // Test checks
    try expect(!addressSet.contains(Relocatable.init(-10, 2)));
}

test "AddressSet: contains should return false if address key does not exist" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    // Test checks
    try expect(!addressSet.contains(Relocatable.init(10, 2)));
}

test "AddressSet: contains should return true if address key is true in address set" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();
    try addressSet.set.put(Relocatable.init(10, 2), true);

    // Test checks
    try expect(addressSet.contains(Relocatable.init(10, 2)));
}

test "AddressSet: addAddresses should add new addresses to the address set without negative indexes" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    const addresses: [4]Relocatable = .{
        Relocatable.init(0, 10),
        Relocatable.init(3, 4),
        Relocatable.init(-2, 2),
        Relocatable.init(23, 7),
    };

    _ = try addressSet.addAddresses(&addresses);

    // Test checks
    try expectEqual(@as(u32, 3), addressSet.set.count());
    try expect(addressSet.set.get(Relocatable.init(0, 10)).?);
    try expect(addressSet.set.get(Relocatable.init(3, 4)).?);
    try expect(addressSet.set.get(Relocatable.init(23, 7)).?);
}

test "AddressSet: len should return the number of addresses in the address set" {
    // Test setup
    var addressSet = AddressSet.init(std.testing.allocator);
    defer addressSet.deinit();

    const addresses: [4]Relocatable = .{
        Relocatable.init(0, 10),
        Relocatable.init(3, 4),
        Relocatable.init(-2, 2),
        Relocatable.init(23, 7),
    };

    _ = try addressSet.addAddresses(&addresses);

    // Test checks
    try expectEqual(@as(u32, 3), addressSet.len());
}

test "MemoryCell: eql function" {
    // Test setup
    const memoryCell1 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    const memoryCell2 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    const memoryCell3 = MemoryCell.init(.{ .felt = Felt252.three() });
    var memoryCell4 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    memoryCell4.is_accessed = true;

    // Test checks
    try expect(memoryCell1.eql(memoryCell2));
    try expect(!memoryCell1.eql(memoryCell3));
    try expect(!memoryCell1.eql(memoryCell4));
}

test "MemoryCell: eqlSlice should return false if slice len are not the same" {
    // Test setup
    const memoryCell1 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    const memoryCell2 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    const memoryCell3 = MemoryCell.init(.{ .felt = Felt252.three() });

    // Test checks
    try expect(!MemoryCell.eqlSlice(
        &[_]?MemoryCell{ memoryCell1, memoryCell2 },
        &[_]?MemoryCell{ memoryCell1, memoryCell2, memoryCell3 },
    ));
}

test "MemoryCell: eqlSlice should return true if same pointer" {
    // Test setup
    const memoryCell1 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    const memoryCell2 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });

    const a = [_]?MemoryCell{ memoryCell1, memoryCell2 };

    // Test checks
    try expect(MemoryCell.eqlSlice(&a, &a));
}

test "MemoryCell: eqlSlice should return false if slice are not equal" {
    // Test setup
    const memoryCell1 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    const memoryCell2 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });

    // Test checks
    try expect(!MemoryCell.eqlSlice(
        &[_]?MemoryCell{ memoryCell1, memoryCell2 },
        &[_]?MemoryCell{ null, memoryCell2 },
    ));
}

test "MemoryCell: eqlSlice should return true if slice are equal" {
    // Test setup
    const memoryCell1 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });
    const memoryCell2 = MemoryCell.init(.{ .felt = Felt252.fromInt(u8, 10) });

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
        MemoryCell.init(MaybeRelocatable.fromSegment(4, 10)).cmp(MemoryCell.init(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with is_accessed set to true and another MemoryCell
    // with the same relocatable segment and offset but is_accessed set to false should result in a less than comparison.
    var memCell = MemoryCell.init(MaybeRelocatable.fromSegment(4, 10));
    memCell.is_accessed = true;
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.init(MaybeRelocatable.fromSegment(4, 10)).cmp(memCell),
    );

    // Testing the opposite of the previous case where is_accessed is set to false for the first MemoryCell,
    // and true for the second MemoryCell with the same relocatable segment and offset. It should result in a greater than comparison.
    try expectEqual(
        std.math.Order.gt,
        memCell.cmp(MemoryCell.init(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a smaller offset compared to another MemoryCell instance
    // with the same segment but a larger offset should result in a less than comparison.
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.init(MaybeRelocatable.fromSegment(4, 5)).cmp(MemoryCell.init(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a larger offset compared to another MemoryCell instance
    // with the same segment but a smaller offset should result in a greater than comparison.
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.init(MaybeRelocatable.fromSegment(4, 15)).cmp(MemoryCell.init(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a smaller segment index compared to another MemoryCell instance
    // with a larger segment index but the same offset should result in a less than comparison.
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.init(MaybeRelocatable.fromSegment(2, 15)).cmp(MemoryCell.init(MaybeRelocatable.fromSegment(4, 10))),
    );

    // Testing if a MemoryCell instance with a larger segment index compared to another MemoryCell instance
    // with a smaller segment index but the same offset should result in a greater than comparison.
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.init(MaybeRelocatable.fromSegment(20, 15)).cmp(MemoryCell.init(MaybeRelocatable.fromSegment(4, 10))),
    );
}

test "MemoryCell: cmp should return an error if incompatible types for a comparison" {
    try expectEqual(
        std.math.Order.lt,
        MemoryCell.init(MaybeRelocatable.fromSegment(
            4,
            10,
        )).cmp(MemoryCell.init(MaybeRelocatable.fromInt(u8, 4))),
    );
    try expectEqual(
        std.math.Order.gt,
        MemoryCell.init(MaybeRelocatable.fromInt(
            u8,
            4,
        )).cmp(MemoryCell.init(MaybeRelocatable.fromSegment(4, 10))),
    );
}

test "MemoryCell: cmp should return proper order results for Felt252 comparisons" {
    // Should return less than (lt) when the first Felt252 is smaller than the second Felt252.
    try expectEqual(std.math.Order.lt, MemoryCell.init(MaybeRelocatable.fromInt(u8, 10)).cmp(MemoryCell.init(MaybeRelocatable.fromInt(u64, 343535))));

    // Should return greater than (gt) when the first Felt252 is larger than the second Felt252.
    try expectEqual(std.math.Order.gt, MemoryCell.init(MaybeRelocatable.fromInt(u256, 543636535)).cmp(MemoryCell.init(MaybeRelocatable.fromInt(u64, 434))));

    // Should return equal (eq) when both Felt252 values are identical.
    try expectEqual(std.math.Order.eq, MemoryCell.init(MaybeRelocatable.fromInt(u8, 10)).cmp(MemoryCell.init(MaybeRelocatable.fromInt(u8, 10))));

    // Should return less than (lt) when the cell's accessed status differs.
    var memCell = MemoryCell.init(MaybeRelocatable.fromInt(u8, 10));
    memCell.is_accessed = true;
    try expectEqual(std.math.Order.lt, MemoryCell.init(MaybeRelocatable.fromInt(u8, 10)).cmp(memCell));

    // Should return greater than (gt) when the cell's accessed status differs (reversed order).
    try expectEqual(std.math.Order.gt, memCell.cmp(MemoryCell.init(MaybeRelocatable.fromInt(u8, 10))));
}

test "MemoryCell: cmp with null values" {
    const memCell = MemoryCell.init(MaybeRelocatable.fromSegment(4, 15));
    const memCell1 = MemoryCell.init(MaybeRelocatable.fromInt(u8, 15));

    try expectEqual(std.math.Order.lt, MemoryCell.cmp(null, memCell));
    try expectEqual(std.math.Order.gt, MemoryCell.cmp(memCell, null));
    try expectEqual(std.math.Order.lt, MemoryCell.cmp(null, memCell1));
    try expectEqual(std.math.Order.gt, MemoryCell.cmp(memCell1, null));
}

test "MemoryCell: cmpSlice should compare MemoryCell slices (if eq and one longer than the other)" {
    const memCell = MemoryCell.init(MaybeRelocatable.fromSegment(4, 15));

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
    const memCell = MemoryCell.init(MaybeRelocatable.fromSegment(4, 15));
    const memCell1 = MemoryCell.init(MaybeRelocatable.fromInt(u8, 15));
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
    const memCell = MemoryCell.init(MaybeRelocatable.fromSegment(40, 15));
    const memCell1 = MemoryCell.init(MaybeRelocatable.fromSegment(3, 15));
    const memCell2 = MemoryCell.init(MaybeRelocatable.fromInt(u8, 10));
    const memCell3 = MemoryCell.init(MaybeRelocatable.fromInt(u8, 15));

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
    const memCell = MemoryCell.init(MaybeRelocatable.fromSegment(40, 15));
    const memCell1 = MemoryCell.init(MaybeRelocatable.fromSegment(3, 15));
    const memCell2 = MemoryCell.init(MaybeRelocatable.fromInt(u8, 10));
    const memCell3 = MemoryCell.init(MaybeRelocatable.fromInt(u8, 15));

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
        Relocatable.init(0, 1),
        .{ .felt = Felt252.fromInt(u8, 23) },
    );
    defer memory.deinitData(std.testing.allocator);

    // Test checks
    try expectError(MemoryError.DuplicatedRelocation, memory.set(
        std.testing.allocator,
        Relocatable.init(0, 1),
        .{ .felt = Felt252.fromInt(u8, 8) },
    ));
}

test "Memory: relocateAddress with some relocation some rules" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Add relocation rules to the Memory instance
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );
    try memory.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(2, 2),
    );

    // Test relocation with rules applied
    try expectEqual(
        MaybeRelocatable.fromRelocatable(Relocatable.init(2, 0)),
        try Memory.relocateAddress(
            Relocatable.init(-1, 0),
            &memory.relocation_rules,
        ),
    );
    try expectEqual(
        MaybeRelocatable.fromRelocatable(Relocatable.init(2, 3)),
        try Memory.relocateAddress(
            Relocatable.init(-2, 1),
            &memory.relocation_rules,
        ),
    );
}

test "Memory: relocateAddress with no relocation rule" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Test relocation without any rules applied
    try expectEqual(
        MaybeRelocatable.fromRelocatable(Relocatable.init(-1, 0)),
        try Memory.relocateAddress(
            Relocatable.init(-1, 0),
            &memory.relocation_rules,
        ),
    );
    try expectEqual(
        MaybeRelocatable.fromRelocatable(Relocatable.init(-2, 1)),
        try Memory.relocateAddress(
            Relocatable.init(-2, 1),
            &memory.relocation_rules,
        ),
    );
    try expectEqual(
        MaybeRelocatable.fromRelocatable(Relocatable.init(1, 0)),
        try Memory.relocateAddress(
            Relocatable.init(1, 0),
            &memory.relocation_rules,
        ),
    );
    try expectEqual(
        MaybeRelocatable.fromRelocatable(Relocatable.init(1, 1)),
        try Memory.relocateAddress(
            Relocatable.init(1, 1),
            &memory.relocation_rules,
        ),
    );
}

test "Memory: relocateValueFromFelt should return the Felt252 value" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Test relocating Felt252 values and assert the expected results
    try expectEqual(Felt252.fromInt(u8, 111), memory.relocateValueFromFelt(Felt252.fromInt(u8, 111)));
    try expectEqual(Felt252.fromInt(u8, 0), memory.relocateValueFromFelt(Felt252.fromInt(u8, 0)));
    try expectEqual(Felt252.fromInt(u8, 1), memory.relocateValueFromFelt(Felt252.fromInt(u8, 1)));
}

test "Memory: relocateValueFromRelocatable with positive segment index" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Add relocation rules for positive segment indices
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );
    try memory.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(2, 2),
    );

    // Test relocating values with positive segment indices and assert the expected results
    try expectEqual(
        Relocatable{},
        try memory.relocateValueFromRelocatable(.{}),
    );
    try expectEqual(
        Relocatable.init(5, 0),
        try memory.relocateValueFromRelocatable(Relocatable.init(5, 0)),
    );
}

test "Memory: relocateValueFromRelocatable with negative segment index (temporary data) without using relocation rule" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Add relocation rules for negative segment indices
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );
    try memory.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(2, 2),
    );

    // Test relocating values with negative segment indices without using relocation rules
    // Assert the expected results
    try expectEqual(
        Relocatable.init(-5, 0),
        try memory.relocateValueFromRelocatable(Relocatable.init(-5, 0)),
    );
}

test "Memory: relocateValueFromRelocatable with negative segment index (temporary data) using relocation rules" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Add relocation rules for negative segment indices
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );
    try memory.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(2, 2),
    );

    // Test relocating values with negative segment indices using relocation rules
    // Assert the expected results for various scenarios
    try expectEqual(
        Relocatable.init(2, 0),
        try memory.relocateValueFromRelocatable(Relocatable.init(-1, 0)),
    );
    try expectEqual(
        Relocatable.init(2, 2),
        try memory.relocateValueFromRelocatable(Relocatable.init(-2, 0)),
    );
    try expectEqual(
        Relocatable.init(2, 5),
        try memory.relocateValueFromRelocatable(Relocatable.init(-1, 5)),
    );
    try expectEqual(
        Relocatable.init(2, 7),
        try memory.relocateValueFromRelocatable(Relocatable.init(-2, 5)),
    );
}

test "Memory: relocateValueFromMaybeRelocatable with Felt252 should return the Felt252" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Test relocating MaybeRelocatable values containing Felt252 and assert the expected results
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 111),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromInt(u8, 111)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 0),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromInt(u8, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 1),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromInt(u8, 1)),
    );
}

test "Memory: relocateValueFromMaybeRelocatable with Relocatable should use relocateValueFromRelocatable" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Add relocation rules for specific segment indices
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );
    try memory.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(2, 2),
    );

    // Test relocating MaybeRelocatable values with segment indices
    // Assert the expected results for different scenarios
    try expectEqual(
        MaybeRelocatable.fromSegment(0, 0),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromSegment(0, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(5, 0),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromSegment(5, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(-5, 0),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromSegment(-5, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 0),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromSegment(-1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 2),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromSegment(-2, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 5),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromSegment(-1, 5)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 7),
        try memory.relocateValueFromMaybeRelocatable(MaybeRelocatable.fromSegment(-2, 5)),
    );
}

test "Memory: getDataFromSegmentIndex should return a pointer to data if segment index is positive or null" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Obtain a reference to the main data within the Memory instance.
    const data_pointer = &memory.data;

    // Test when the segment index is positive (15), should return a pointer to the main data.
    try expectEqual(data_pointer, memory.getDataFromSegmentIndex(15));

    // Test when the segment index is the maximum positive value, should still return a pointer to the main data.
    try expectEqual(data_pointer, memory.getDataFromSegmentIndex(std.math.maxInt(i64)));

    // Test when the segment index is 0, should return a pointer to the main data.
    try expectEqual(data_pointer, memory.getDataFromSegmentIndex(0));
}

test "Memory: getDataFromSegmentIndex should return a pointer to data_temp if segment index is negative" {
    // Create a new Memory instance using the testing allocator
    var memory = try Memory.init(std.testing.allocator);
    // Defer memory deallocation to ensure proper cleanup
    defer memory.deinit();

    // Obtain a reference to the temporary data within the Memory instance.
    const data_pointer = &memory.temp_data;

    // Test when the segment index is negative (-15), should return a pointer to the temporary data.
    try expectEqual(data_pointer, memory.getDataFromSegmentIndex(-15));

    // Test when the segment index is the maximum negative value, should still return a pointer to the temporary data.
    try expectEqual(data_pointer, memory.getDataFromSegmentIndex(-std.math.maxInt(i64)));
}

test "Memory: relocateMemory with empty relocation rules" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Invoke the relocation process.
    try memory.relocateMemory();

    // Verify the relocation results using expectEqual.
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 1),
        memory.get(.{}),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 2),
        memory.get(Relocatable.init(0, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 3),
        memory.get(Relocatable.init(0, 2)),
    );
}

test "Memory: relocateMemory with new segment and gap" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including new segments and gaps.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{7} },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to redirect a temporary segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 1),
    );

    // Append an empty segment to the main data.
    try memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});

    // Ensure that temporary data is not empty before relocation.
    try expect(!(memory.temp_data.items.len == 0));

    // Invoke the relocation process.
    try memory.relocateMemory();

    // Verify the relocation results using expectEqual.
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 1),
        memory.get(.{}),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 1),
        memory.get(Relocatable.init(0, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 3),
        memory.get(Relocatable.init(0, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 2),
        memory.get(Relocatable.init(1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 5),
        memory.get(Relocatable.init(1, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 3),
        memory.get(Relocatable.init(1, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 7),
        memory.get(Relocatable.init(2, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 8),
        memory.get(Relocatable.init(2, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 9),
        memory.get(Relocatable.init(2, 3)),
    );

    // Ensure that temporary data is empty after relocation.
    try expect(memory.temp_data.items.len == 0);
}

test "Memory: relocateMemory with new segment" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including new segments.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{7} },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to redirect a temporary segment to a new segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );

    // Append an empty segment to the main data.
    try memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});

    // Ensure that temporary data is not empty before relocation.
    try expect(!(memory.temp_data.items.len == 0));

    // Invoke the relocation process.
    try memory.relocateMemory();

    // Verify the relocation results using expectEqual.
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 1),
        memory.get(.{}),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 0),
        memory.get(Relocatable.init(0, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 3),
        memory.get(Relocatable.init(0, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 1),
        memory.get(Relocatable.init(1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 5),
        memory.get(Relocatable.init(1, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 2),
        memory.get(Relocatable.init(1, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 7),
        memory.get(Relocatable.init(2, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 8),
        memory.get(Relocatable.init(2, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 9),
        memory.get(Relocatable.init(2, 2)),
    );

    // Ensure that temporary data is empty after relocation.
    try expect(memory.temp_data.items.len == 0);
}

test "Memory: relocateMemory with new segment unallocated" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including new segments.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{7} },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to redirect a temporary segment to a new segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );

    // Expect an error due to an attempt to relocate an unallocated segment.
    try expectError(
        MemoryError.UnallocatedSegment,
        memory.relocateMemory(),
    );
}

test "Memory: relocateMemory into an existing segment" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including existing segments.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{7} },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to relocate a temporary segment into an existing segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(1, 3),
    );

    // Expect the temporary segment to be non-empty.
    try expect(!(memory.temp_data.items.len == 0));

    // Perform memory relocation.
    try memory.relocateMemory();

    // Expect values in memory after relocation.
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 1),
        memory.get(.{}),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 3),
        memory.get(Relocatable.init(0, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 3),
        memory.get(Relocatable.init(0, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 4),
        memory.get(Relocatable.init(1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 5),
        memory.get(Relocatable.init(1, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 5),
        memory.get(Relocatable.init(1, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 7),
        memory.get(Relocatable.init(1, 3)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 8),
        memory.get(Relocatable.init(1, 4)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 9),
        memory.get(Relocatable.init(1, 5)),
    );

    // Expect the temporary segment to be empty after relocation.
    try expect(memory.temp_data.items.len == 0);
}

test "Memory: relocateMemory into an existing segment with inconsistent memory" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including existing segments.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{7} },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to relocate a temporary segment into an existing segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(1, 0),
    );

    // Expect an error due to inconsistent memory after relocation.
    try expectError(
        MemoryError.DuplicatedRelocation,
        memory.relocateMemory(),
    );
}

test "Memory: relocateMemory into new segment with two temporary segments and one relocated" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including existing segments.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{7} },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
            .{ .{ -2, 0 }, .{10} },
            .{ .{ -2, 1 }, .{11} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to relocate a temporary segment into a new segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );

    // Append a new empty segment to data.
    try memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});

    // Perform memory relocation.
    try memory.relocateMemory();

    // Expectations for the relocated memory after relocation.
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 1),
        memory.get(.{}),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 0),
        memory.get(Relocatable.init(0, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 3),
        memory.get(Relocatable.init(0, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 1),
        memory.get(Relocatable.init(1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 5),
        memory.get(Relocatable.init(1, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 2),
        memory.get(Relocatable.init(1, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 7),
        memory.get(Relocatable.init(2, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 8),
        memory.get(Relocatable.init(2, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 9),
        memory.get(Relocatable.init(2, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 10),
        memory.get(Relocatable.init(-1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 11),
        memory.get(Relocatable.init(-1, 1)),
    );
}

test "Memory: relocateMemory into new segment with two temporary segments and two relocated" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including existing segments.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{7} },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
            .{ .{ -2, 0 }, .{10} },
            .{ .{ -2, 1 }, .{11} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to relocate a temporary segment into a new segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(2, 0),
    );
    // Append a new empty segment to data.
    try memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});
    // Add another relocation rule to relocate a temporary segment into a new segment.
    try memory.addRelocationRule(
        Relocatable.init(-2, 0),
        Relocatable.init(3, 0),
    );
    // Append another new empty segment to data.
    try memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});

    // Perform memory relocation.
    try memory.relocateMemory();

    // Expectations for the relocated memory after relocation.
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 1),
        memory.get(.{}),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 0),
        memory.get(Relocatable.init(0, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 3),
        memory.get(Relocatable.init(0, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 1),
        memory.get(Relocatable.init(1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 5),
        memory.get(Relocatable.init(1, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(2, 2),
        memory.get(Relocatable.init(1, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 7),
        memory.get(Relocatable.init(2, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 8),
        memory.get(Relocatable.init(2, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 9),
        memory.get(Relocatable.init(2, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 10),
        memory.get(Relocatable.init(3, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 11),
        memory.get(Relocatable.init(3, 1)),
    );

    // Ensure temporary data is empty after relocation.
    try expect(memory.temp_data.items.len == 0);
}

test "Memory: relocateMemory into an existing segment with temporary values in temporary memory" {
    // Initialize Memory instance.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure memory is deallocated after the test.
    defer memory.deinit();

    // Set up memory with predefined data, including existing segments.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{ -1, 0 } },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 1, 0 }, .{ -1, 1 } },
            .{ .{ 1, 1 }, .{5} },
            .{ .{ 1, 2 }, .{ -1, 2 } },
            .{ .{ -1, 0 }, .{ -1, 0 } },
            .{ .{ -1, 1 }, .{8} },
            .{ .{ -1, 2 }, .{9} },
        },
    );
    // Ensure data memory is deallocated after the test.
    defer memory.deinitData(std.testing.allocator);

    // Add a relocation rule to relocate a temporary segment into an existing segment.
    try memory.addRelocationRule(
        Relocatable.init(-1, 0),
        Relocatable.init(1, 3),
    );
    // Append a new empty segment to data.
    try memory.data.append(std.ArrayListUnmanaged(?MemoryCell){});

    // Perform memory relocation.
    try memory.relocateMemory();

    // Expectations for the relocated memory after relocation.
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 1),
        memory.get(.{}),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 3),
        memory.get(Relocatable.init(0, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 3),
        memory.get(Relocatable.init(0, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 4),
        memory.get(Relocatable.init(1, 0)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 5),
        memory.get(Relocatable.init(1, 1)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 5),
        memory.get(Relocatable.init(1, 2)),
    );
    try expectEqual(
        MaybeRelocatable.fromSegment(1, 3),
        memory.get(Relocatable.init(1, 3)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 8),
        memory.get(Relocatable.init(1, 4)),
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u64, 9),
        memory.get(Relocatable.init(1, 5)),
    );

    // Ensure temporary data is empty after relocation.
    try expect(memory.temp_data.items.len == 0);
}
