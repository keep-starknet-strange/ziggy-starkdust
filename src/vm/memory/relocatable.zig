const std = @import("std");
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const CairoVMError = @import("../error.zig").CairoVMError;
const MathError = @import("../error.zig").MathError;
const MemoryError = @import("../error.zig").MemoryError;

// Relocatable in the Cairo VM represents an address
// in some memory segment. When the VM finishes running,
// these values are replaced by real memory addresses,
// represented by a field element.
pub const Relocatable = struct {
    const Self = @This();

    // The index of the memory segment.
    segment_index: i64 = 0,
    // The offset in the memory segment.
    offset: u64 = 0,

    // Creates a new Relocatable.
    // # Arguments
    // - segment_index - The index of the memory segment.
    // - offset - The offset in the memory segment.
    // # Returns
    // A new Relocatable.
    pub fn new(segment_index: i64, offset: u64) Self {
        return .{ .segment_index = segment_index, .offset = offset };
    }

    // Determines if this Relocatable is equal to another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if they are equal, `false` otherwise.
    pub fn eq(self: Self, other: Self) bool {
        return self.segment_index == other.segment_index and self.offset == other.offset;
    }

    // Determines if this Relocatable is less than another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is less than other, `false` otherwise.
    pub fn lt(self: Self, other: Self) bool {
        return self.segment_index < other.segment_index or (self.segment_index == other.segment_index and self.offset < other.offset);
    }

    // Determines if this Relocatable is less than or equal to another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is less than or equal to other, `false` otherwise.
    pub fn le(self: Self, other: Self) bool {
        return self.segment_index < other.segment_index or (self.segment_index == other.segment_index and self.offset <= other.offset);
    }

    // Determines if this Relocatable is greater than another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is greater than other, `false` otherwise.
    pub fn gt(self: Self, other: Self) bool {
        return self.segment_index > other.segment_index or (self.segment_index == other.segment_index and self.offset > other.offset);
    }

    // Determines if this Relocatable is greater than or equal to another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is greater than or equal to other, `false` otherwise.
    pub fn ge(self: Self, other: Self) bool {
        return self.segment_index > other.segment_index or (self.segment_index == other.segment_index and self.offset >= other.offset);
    }

    /// Compares this Relocatable with another.
    ///
    /// # Arguments
    ///
    /// - `other`: The other Relocatable to compare to.
    ///
    /// # Returns
    ///
    /// Returns `.lt` if this Relocatable is less than `other`, `.gt` if it's greater,
    /// and `.eq` if they are equal based on their segment_index and offset.
    pub fn cmp(self: Self, other: Self) std.math.Order {
        return switch (std.math.order(self.segment_index, other.segment_index)) {
            .eq => std.math.order(self.offset, other.offset),
            else => |res| res,
        };
    }

    /// Attempts to subtract a `Relocatable` from another.
    ///
    /// This method fails if `self` and other` are not from the same segment.
    pub fn sub(self: Self, other: Self) !Self {
        if (self.segment_index != other.segment_index) {
            return CairoVMError.TypeMismatchNotRelocatable;
        }

        return try subUint(self, other.offset);
    }

    /// Attempts to subtract a Felt252 value from this Relocatable.
    ///
    /// This method internally converts `other` into a `u64` and performs subtraction.
    /// # Arguments
    /// - self: The Relocatable value to subtract from.
    /// - other: The Felt252 value to subtract from `self.offset`.
    /// # Returns
    /// A new Relocatable after the subtraction operation.
    /// # Errors
    /// An error is returned if the subtraction results in an underflow (negative value).
    pub fn subFelt(self: Self, other: Felt252) MathError!Self {
        return try self.subUint(try other.tryIntoU64());
    }

    // Substract a u64 from a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The u64 to substract.
    // # Returns
    // A new Relocatable.
    pub fn subUint(self: Self, other: u64) !Self {
        if (self.offset < other) {
            return MathError.RelocatableSubUsizeNegOffset;
        }
        return .{
            .segment_index = self.segment_index,
            .offset = self.offset - other,
        };
    }

    // Add a u64 to a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The u64 to add.
    // # Returns
    // A new Relocatable.
    pub fn addUint(self: Self, other: u64) !Self {
        return .{
            .segment_index = self.segment_index,
            .offset = self.offset + other,
        };
    }

    /// Add a u64 to this Relocatable, modifying it in place.
    /// # Arguments
    /// - self: Pointer to the Relocatable object to modify.
    /// - other: The u64 to add to `self.offset`.
    pub fn addUintInPlace(self: *Self, other: u64) void {
        // Modify the offset of the existing Relocatable object
        self.offset += other;
    }

    // Add a i64 to a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The i64 to add.
    // # Returns
    // A new Relocatable.
    pub fn addInt(self: Self, other: i64) !Self {
        if (other < 0) {
            return self.subUint(@as(
                u64,
                @intCast(
                    -other,
                ),
            ));
        }
        return self.addUint(@as(
            u64,
            @intCast(
                other,
            ),
        ));
    }

    /// Adds a Felt252 value to this Relocatable.
    ///
    /// This method adds `other` to the current `offset` of the Relocatable.
    /// # Arguments
    /// - self: The Relocatable value to add to.
    /// - other: The Felt252 value to add to `self.offset`.
    /// # Returns
    /// A new Relocatable after the addition operation.
    /// # Errors
    /// An error is returned if the addition results in an overflow (exceeding u64).
    pub fn addFelt(self: Self, other: Felt252) MathError!Self {
        return .{
            .segment_index = self.segment_index,
            .offset = try Felt252.fromInteger(@intCast(self.offset)).add(other).tryIntoU64(),
        };
    }

    /// Add a felt to this Relocatable, modifying it in place.
    /// # Arguments
    /// - self: Pointer to the Relocatable object to modify.
    /// - other: The felt to add to `self.offset`.
    pub fn addFeltInPlace(self: *Self, other: Felt252) !void {
        self.offset = try Felt252.fromInteger(@intCast(self.offset)).add(other).tryIntoU64();
    }

    /// Performs additions if other contains a Felt value, fails otherwise.
    /// # Arguments
    /// - other - The other MaybeRelocatable to add.
    pub fn addMaybeRelocatableInplace(self: *Self, other: MaybeRelocatable) !void {
        try self.addFeltInPlace(try other.tryIntoFelt());
    }

    /// Calculates the relocated address based on the provided relocation_table.
    ///
    /// This function determines the relocated memory address corresponding to the `Relocatable`
    /// instance within a given relocation_table. It performs relocation by fetching the segment_index
    /// from the relocation_table and adding the offset. It handles temporary segment scenarios and
    /// relocation errors.
    ///
    /// # Arguments
    /// - self: Pointer to the Relocatable object to relocate.
    /// - relocation_table: An array representing relocation information.
    ///
    /// # Returns
    /// - `usize` value: The relocated memory address.
    ///
    /// # Errors
    /// - Returns a `MemoryError` in case of relocation failure or encountering a temporary segment.
    pub fn relocateAddress(self: *const Self, relocation_table: []usize) MemoryError!usize {
        if (self.segment_index >= 0) {
            if (relocation_table.len <= self.segment_index) {
                return MemoryError.Relocation;
            }
            return @intCast(relocation_table[@intCast(self.segment_index)] + self.offset);
        }
        return MemoryError.TemporarySegmentInRelocation;
    }
};

// MaybeRelocatable is the type of the memory cells in the Cairo
// VM. It can either be a Relocatable or a field element.
pub const MaybeRelocatable = union(enum) {
    const Self = @This();

    relocatable: Relocatable,
    felt: Felt252,

    /// Determines if two `MaybeRelocatable` instances are equal.
    ///
    /// This method compares the variant type and the contained value. If both the variant
    /// and the value are identical between the two instances, they are considered equal.
    ///
    /// ## Arguments:
    ///   * other: The other `MaybeRelocatable` instance to compare against.
    ///
    /// ## Returns:
    ///   * `true` if the two instances are equal.
    ///   * `false` otherwise.
    pub fn eq(self: Self, other: Self) bool {
        // Switch on the type of `self`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // Compare the `relocatable` values if both `self` and `other` are `relocatable`
                .relocatable => |other_value| self_value.eq(other_value),
                // If `self` is `relocatable` and `other` is `felt`, they are not equal
                .felt => false,
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // Compare the `felt` values if both `self` and `other` are `felt`
                .felt => self_value.equal(other.felt),
                // If `self` is `felt` and `other` is `relocatable`, they are not equal
                .relocatable => false,
            },
        };
    }

    /// Determines if self is less than other.
    ///
    /// ## Arguments:
    ///   * other: The other `MaybeRelocatable` instance to compare against.
    ///
    /// ## Returns:
    ///   * `true` if self is less than other
    ///   * `false` otherwise.
    pub fn lt(self: Self, other: Self) bool {
        // Switch on the type of `self`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // Compare the `relocatable` values if both `self` and `other` are `relocatable`
                .relocatable => |other_value| self_value.lt(other_value),
                // If `self` is `relocatable` and `other` is `felt`, they are not equal
                .felt => false,
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // Compare the `felt` values if both `self` and `other` are `felt`
                .felt => self_value.lt(other.felt),
                // If `self` is `felt` and `other` is `relocatable`, they are not equal
                .relocatable => false,
            },
        };
    }

    /// Determines if self is less than or equal to other.
    ///
    /// ## Arguments:
    ///   * other: The other `MaybeRelocatable` instance to compare against.
    ///
    /// ## Returns:
    ///   * `true` if self is less than or equal to other
    ///   * `false` otherwise.
    pub fn le(self: Self, other: Self) bool {
        // Switch on the type of `self`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // Compare the `relocatable` values if both `self` and `other` are `relocatable`
                .relocatable => |other_value| self_value.le(other_value),
                // If `self` is `relocatable` and `other` is `felt`, they are not equal
                .felt => false,
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // Compare the `felt` values if both `self` and `other` are `felt`
                .felt => self_value.le(other.felt),
                // If `self` is `felt` and `other` is `relocatable`, they are not equal
                .relocatable => false,
            },
        };
    }

    /// Determines if self is greater than other.
    ///
    /// ## Arguments:
    ///   * other: The other `MaybeRelocatable` instance to compare against.
    ///
    /// ## Returns:
    ///   * `true` if self is greater than other
    ///   * `false` otherwise.
    pub fn gt(self: Self, other: Self) bool {
        // Switch on the type of `self`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // Compare the `relocatable` values if both `self` and `other` are `relocatable`
                .relocatable => |other_value| self_value.gt(other_value),
                // If `self` is `relocatable` and `other` is `felt`, they are not equal
                .felt => false,
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // Compare the `felt` values if both `self` and `other` are `felt`
                .felt => self_value.gt(other.felt),
                // If `self` is `felt` and `other` is `relocatable`, they are not equal
                .relocatable => false,
            },
        };
    }

    /// Determines if self is greater than or equal to other.
    ///
    /// ## Arguments:
    ///   * other: The other `MaybeRelocatable` instance to compare against.
    ///
    /// ## Returns:
    ///   * `true` if self is greater than other
    ///   * `false` otherwise.
    pub fn ge(self: Self, other: Self) bool {
        // Switch on the type of `self`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // Compare the `relocatable` values if both `self` and `other` are `relocatable`
                .relocatable => |other_value| self_value.ge(other_value),
                // If `self` is `relocatable` and `other` is `felt`, they are not equal
                .felt => false,
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // Compare the `felt` values if both `self` and `other` are `felt`
                .felt => self_value.ge(other.felt),
                // If `self` is `felt` and `other` is `relocatable`, they are not equal
                .relocatable => false,
            },
        };
    }

    /// Compares this `MaybeRelocatable` with another `MaybeRelocatable` instance.
    ///
    /// This function performs a comparison between two `MaybeRelocatable` instances, taking into account their variant types
    /// and contained values. If the variant types or values are incompatible for comparison, it returns an error.
    ///
    /// # Arguments
    ///
    /// - `other`: The other `MaybeRelocatable` instance to compare against.
    ///
    /// # Returns
    ///
    /// Returns `.lt` if `self` is less than `other`, `.gt` if it's greater,
    /// and `.eq` if they are equal based on their `segment_index` and `offset` values.
    ///
    /// Returns `MathError.IncompatibleComparisonTypes` if the comparison involves incompatible types.
    pub fn cmp(self: Self, other: Self) std.math.Order {
        // Compare the `self` variant type against `other`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // If `other` is also `relocatable`, compare the `relocatable` values
                .relocatable => |other_value| self_value.cmp(other_value),
                // If `other` is `felt`, the comparison is invalid, return an error
                .felt => .lt,
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // If `other` is also `felt`, compare the `felt` values
                .felt => self_value.cmp(other.felt),
                // If `other` is `relocatable`, the comparison is invalid, return an error
                .relocatable => .gt,
            },
        };
    }

    /// Return the value of the MaybeRelocatable as a felt or error.
    /// # Returns
    /// The value of the MaybeRelocatable as a Relocatable felt or error.
    pub fn tryIntoFelt(self: Self) CairoVMError!Felt252 {
        return switch (self) {
            .relocatable => CairoVMError.TypeMismatchNotFelt,
            .felt => |felt| felt,
        };
    }

    /// Return the value of the MaybeRelocatable as a felt or error.
    /// # Returns
    /// The value of the MaybeRelocatable as a Relocatable felt or error.
    pub fn tryIntoU64(self: Self) error{
        TypeMismatchNotFelt,
        ValueTooLarge,
    }!u64 {
        return switch (self) {
            .relocatable => CairoVMError.TypeMismatchNotFelt,
            .felt => |felt| felt.tryIntoU64(),
        };
    }

    /// Return the value of the MaybeRelocatable as a Relocatable.
    /// # Returns
    /// The value of the MaybeRelocatable as a Relocatable.
    pub fn tryIntoRelocatable(self: Self) CairoVMError!Relocatable {
        return switch (self) {
            .relocatable => |relocatable| relocatable,
            .felt => CairoVMError.TypeMismatchNotRelocatable,
        };
    }

    /// Whether the MaybeRelocatable is zero or not.
    /// # Returns
    /// true if the MaybeRelocatable is zero, false otherwise.
    pub fn isZero(self: Self) bool {
        return switch (self) {
            .relocatable => false,
            .felt => |felt| felt.isZero(),
        };
    }

    /// Whether the MaybeRelocatable is a relocatable or not.
    /// # Returns
    /// true if the MaybeRelocatable is a relocatable, false otherwise.
    pub fn isRelocatable(self: MaybeRelocatable) bool {
        return std.meta.activeTag(self) == .relocatable;
    }

    /// Returns whether the MaybeRelocatable is a felt or not.
    ///
    /// # Returns
    ///
    /// `true` if the MaybeRelocatable is a felt, `false` otherwise.
    pub fn isFelt(self: MaybeRelocatable) bool {
        return std.meta.activeTag(self) == .felt;
    }

    /// Adds two MaybeRelocatable values together.
    ///
    /// This method performs addition between two MaybeRelocatable instances, either Relocatable
    /// or Felt252. It switches based on the type of `self` and `other` to perform the correct addition.
    ///
    /// # Arguments:
    ///   * self: The first MaybeRelocatable value.
    ///   * other: The second MaybeRelocatable value to add to `self`.
    ///
    /// # Returns:
    ///   * A new MaybeRelocatable value after the addition operation.
    ///   * An error in case of type mismatch or specific math errors.
    pub fn add(self: Self, other: Self) MathError!Self {
        // Switch on the type of `self`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // If `other` is also `relocatable`, addition is not supported, return an error
                .relocatable => MathError.RelocatableAdd,
                // If `other` is `felt`, call `addFelt` method on `self_value`
                .felt => |fe| .{ .relocatable = try self_value.addFelt(fe) },
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // If `other` is also `felt`, perform addition on `self_value`
                .felt => |fe| .{ .felt = self_value.add(fe) },
                // If `other` is `relocatable`, call `addFelt` method on `other` with `self_value`
                .relocatable => |r| .{ .relocatable = try r.addFelt(self_value) },
            },
        };
    }

    /// Subtracts one MaybeRelocatable value from another.
    ///
    /// This method performs subtraction between two MaybeRelocatable instances, either Relocatable
    /// or Felt252. It switches based on the type of `self` and `other` to perform the correct subtraction.
    ///
    /// # Arguments:
    ///   * self: The MaybeRelocatable value to subtract from.
    ///   * other: The MaybeRelocatable value to subtract from `self`.
    ///
    /// # Returns:
    ///   * A new MaybeRelocatable value after the subtraction operation.
    ///   * An error in case of type mismatch or specific math errors.
    pub fn sub(self: Self, other: Self) !Self {
        // Switch on the type of `self`
        return switch (self) {
            // If `self` is of type `relocatable`
            .relocatable => |self_value| switch (other) {
                // If `other` is also `relocatable`, call `sub` method on `self_value`
                .relocatable => |r| .{ .relocatable = try self_value.sub(r) },
                // If `other` is `felt`, call `subFelt` method on `self_value`
                .felt => |fe| .{ .relocatable = try self_value.subFelt(fe) },
            },
            // If `self` is of type `felt`
            .felt => |self_value| switch (other) {
                // If `other` is also `felt`, perform subtraction on `self_value`
                .felt => |fe| .{ .felt = self_value.sub(fe) },
                // If `other` is `relocatable`, return an error as subtraction is not supported
                .relocatable => MathError.SubRelocatableFromInt,
            },
        };
    }

    /// Converts a `MaybeRelocatable` instance into a `Felt252` value, considering relocation.
    ///
    /// This function handles the conversion of a `MaybeRelocatable` instance, identifying whether
    /// it contains a `Felt252` value or a `Relocatable`. In the case of a `Relocatable`, it utilizes
    /// the `relocateAddress` method to obtain the relocated address and converts it into a `Felt252`.
    ///
    /// # Arguments
    /// - `self`: Pointer to the MaybeRelocatable object to convert.
    /// - `relocation_table`: An array representing relocation information.
    ///
    /// # Returns
    /// - `Felt252`: The converted Felt252 value.
    ///
    /// # Errors
    /// - Returns a `MemoryError` if encountering relocation issues or mismatches in the conversion.
    pub fn relocateValue(self: *const Self, relocation_table: []usize) MemoryError!Felt252 {
        return switch (self.*) {
            .felt => |fe| fe,
            .relocatable => |r| Felt252.fromInteger(try r.relocateAddress(relocation_table)),
        };
    }

    /// Creates a new MaybeRelocatable from a Relocatable.
    /// # Arguments
    /// - relocatable - The Relocatable to create the MaybeRelocatable from.
    /// # Returns
    /// A new MaybeRelocatable.
    pub fn fromRelocatable(relocatable: Relocatable) Self {
        return .{ .relocatable = relocatable };
    }

    /// Creates a new MaybeRelocatable from a field element.
    /// # Arguments
    /// - felt - The field element to create the MaybeRelocatable from.
    /// # Returns
    /// A new MaybeRelocatable.
    pub fn fromFelt(felt: Felt252) Self {
        return .{ .felt = felt };
    }

    /// Creates a new MaybeRelocatable from a u256.
    /// # Arguments
    /// - value - The u64 to create the MaybeRelocatable from.
    /// # Returns
    /// A new MaybeRelocatable.
    pub fn fromU256(value: u256) Self {
        return .{ .felt = Felt252.fromInteger(value) };
    }

    /// Creates a new MaybeRelocatable from a u64.
    /// # Arguments
    /// - value - The u64 to create the MaybeRelocatable from.
    /// # Returns
    /// A new MaybeRelocatable.
    pub fn fromU64(value: u64) Self {
        return fromU256(@intCast(value));
    }

    /// Creates a new MaybeRelocatable from a segment index and an offset.
    /// # Arguments
    /// - segment_index - The i64 for segment_index
    /// - offset - The u64 for offset
    /// # Returns
    /// A new MaybeRelocatable.
    pub fn fromSegment(segment_index: i64, offset: u64) Self {
        return fromRelocatable(Relocatable.new(segment_index, offset));
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Relocatable: eq should return true if two Relocatable are the same." {
    try expect(Relocatable.new(-1, 4).eq(Relocatable.new(-1, 4)));
    try expect(Relocatable.new(2, 4).eq(Relocatable.new(2, 4)));
}

test "Relocatable: eq should return false if two Relocatable are not the same." {
    const relocatable1 = Relocatable.new(2, 4);
    const relocatable2 = Relocatable.new(2, 5);
    const relocatable3 = Relocatable.new(-1, 4);
    try expect(!relocatable1.eq(relocatable2));
    try expect(!relocatable1.eq(relocatable3));
}

test "Relocatable: addUint should add a u64 to a Relocatable and return a new Relocatable." {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = try relocatable.addUint(24);
    const expected = Relocatable.new(
        2,
        28,
    );
    try expectEqual(
        expected,
        result,
    );
}

test "Relocatable: addInt should add a positive i64 to a Relocatable and return a new Relocatable" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = try relocatable.addInt(24);
    const expected = Relocatable.new(
        2,
        28,
    );
    try expectEqual(
        expected,
        result,
    );
}

test "Relocatable: addInt should add a negative i64 to a Relocatable and return a new Relocatable" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = try relocatable.addInt(-4);
    const expected = Relocatable.new(
        2,
        0,
    );
    try expectEqual(
        expected,
        result,
    );
}

test "Relocatable: subUint should substract a u64 from a Relocatable" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = try relocatable.subUint(2);
    const expected = Relocatable.new(
        2,
        2,
    );
    try expectEqual(
        expected,
        result,
    );
}

test "Relocatable: subUint should return an error if substraction is impossible" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = relocatable.subUint(6);
    try expectError(
        MathError.RelocatableSubUsizeNegOffset,
        result,
    );
}

test "Relocatable: sub two Relocatable with same segment index" {
    try expectEqual(
        Relocatable.new(2, 3),
        try Relocatable.new(2, 8).sub(Relocatable.new(2, 5)),
    );
}

test "Relocatable: sub two Relocatable with same segment index but impossible subtraction" {
    try expectError(
        MathError.RelocatableSubUsizeNegOffset,
        Relocatable.new(2, 2).sub(Relocatable.new(2, 5)),
    );
}

test "Relocatable: sub two Relocatable with different segment index" {
    try expectError(
        CairoVMError.TypeMismatchNotRelocatable,
        Relocatable.new(2, 8).sub(Relocatable.new(3, 5)),
    );
}

test "Relocatable: addUintInPlace should increase offset" {
    var relocatable = Relocatable.new(2, 8);
    relocatable.addUintInPlace(10);
    try expectEqual(
        Relocatable.new(2, 18),
        relocatable,
    );
}

test "Relocatable: addFeltInPlace should increase offset" {
    var relocatable = Relocatable.new(2, 8);
    try relocatable.addFeltInPlace(Felt252.fromInteger(1000000000000000));
    try expectEqual(
        Relocatable.new(2, 1000000000000008),
        relocatable,
    );
}

test "Relocatable: addMaybeRelocatableInplace should increase offset if other is Felt" {
    var relocatable = Relocatable.new(2, 8);
    try relocatable.addMaybeRelocatableInplace(MaybeRelocatable{ .felt = Felt252.fromInteger(1000000000000000) });
    try expectEqual(
        Relocatable.new(2, 1000000000000008),
        relocatable,
    );
}

test "Relocatable: addMaybeRelocatableInplace should return an error if other is Relocatable" {
    var relocatable = Relocatable.new(2, 8);
    try expectError(
        CairoVMError.TypeMismatchNotFelt,
        relocatable.addMaybeRelocatableInplace(MaybeRelocatable{ .relocatable = Relocatable.new(
            0,
            10,
        ) }),
    );
}

test "Relocatable: lt should return true if other relocatable is greater than or equal, false otherwise" {
    // 1 == 2
    try expect(!Relocatable.new(2, 4).lt(Relocatable.new(2, 4)));

    // 1 < 2
    try expect(Relocatable.new(-1, 2).lt(Relocatable.new(-1, 3)));
    try expect(Relocatable.new(1, 5).lt(Relocatable.new(2, 4)));

    // 1 > 2
    try expect(!Relocatable.new(2, 5).lt(Relocatable.new(2, 4)));
    try expect(!Relocatable.new(3, 3).lt(Relocatable.new(2, 4)));
}

test "Relocatable: le should return true if other relocatable is greater, false otherwise" {
    // 1 == 2
    try expect(Relocatable.new(2, 4).le(Relocatable.new(2, 4)));

    // 1 < 2
    try expect(Relocatable.new(-1, 2).le(Relocatable.new(-1, 3)));
    try expect(Relocatable.new(1, 5).le(Relocatable.new(2, 4)));

    // 1 > 2
    try expect(!Relocatable.new(2, 5).le(Relocatable.new(2, 4)));
    try expect(!Relocatable.new(3, 3).le(Relocatable.new(2, 4)));
}

test "Relocatable: gt should return true if other relocatable is less than or 1 == 2ual, false otherwise" {
    // 1 == 2
    try expect(!Relocatable.new(2, 4).gt(Relocatable.new(2, 4)));

    // 1 < 2
    try expect(!Relocatable.new(-1, 2).gt(Relocatable.new(-1, 3)));
    try expect(!Relocatable.new(1, 5).gt(Relocatable.new(2, 4)));

    // 1 > 2
    try expect(Relocatable.new(2, 5).gt(Relocatable.new(2, 4)));
    try expect(Relocatable.new(3, 3).gt(Relocatable.new(2, 4)));
}

test "Relocatable: ge should return true if other relocatable is less, false otherwise" {
    // 1 == 2
    try expect(Relocatable.new(2, 4).ge(Relocatable.new(2, 4)));

    // 1 < 2
    try expect(!Relocatable.new(-1, 2).ge(Relocatable.new(-1, 3)));
    try expect(!Relocatable.new(1, 5).ge(Relocatable.new(2, 4)));

    // 1 > 2
    try expect(Relocatable.new(2, 5).ge(Relocatable.new(2, 4)));
    try expect(Relocatable.new(3, 3).ge(Relocatable.new(2, 4)));
}

test "Relocatable: cmpt should return .eq if self and other are the same" {
    try expectEqual(
        std.math.Order.eq,
        Relocatable.new(2, 4).cmp(Relocatable.new(2, 4)),
    );
}

test "Relocatable: cmpt should return .lt if self and other segment are the same but self offset < other offset" {
    try expectEqual(
        std.math.Order.lt,
        Relocatable.new(2, 2).cmp(Relocatable.new(2, 4)),
    );
}

test "Relocatable: cmpt should return .gt if self and other segment are the same but self offset > other offset" {
    try expectEqual(
        std.math.Order.gt,
        Relocatable.new(2, 14).cmp(Relocatable.new(2, 4)),
    );
}

test "Relocatable: cmpt should return .lt if self segment < other segment" {
    try expectEqual(
        std.math.Order.lt,
        Relocatable.new(1, 4).cmp(Relocatable.new(2, 4)),
    );
    try expectEqual(
        std.math.Order.lt,
        Relocatable.new(1, 44).cmp(Relocatable.new(2, 4)),
    );
}

test "Relocatable: cmpt should return .gt if self segment > other segment" {
    try expectEqual(
        std.math.Order.gt,
        Relocatable.new(10, 4).cmp(Relocatable.new(2, 4)),
    );
    try expectEqual(
        std.math.Order.gt,
        Relocatable.new(10, 4).cmp(Relocatable.new(2, 44)),
    );
}

test "Relocatable: addFelt should add a relocatable and a Felt252" {
    try expectEqual(
        Relocatable{ .segment_index = 2, .offset = 54 },
        try Relocatable.new(2, 44).addFelt(Felt252.fromInteger(10)),
    );
}

test "Relocatable: addFelt should return an error if number after offset addition is too large" {
    try expectError(
        MathError.ValueTooLarge,
        Relocatable.new(2, 44).addFelt(Felt252.fromInteger(std.math.maxInt(u256))),
    );
}

test "Relocatable: subFelt should subtract a Felt252 from a relocatable" {
    try expectEqual(
        Relocatable{ .segment_index = 2, .offset = 34 },
        try Relocatable.new(2, 44).subFelt(Felt252.fromInteger(10)),
    );
}

test "Relocatable: subFelt should return an error if relocatable cannot be coerced to u64" {
    try expectError(
        MathError.ValueTooLarge,
        Relocatable.new(2, 44).subFelt(Felt252.fromInteger(std.math.maxInt(u256))),
    );
}

test "Relocatable: subFelt should return an error if relocatable offset is smaller than Felt252" {
    try expectError(
        MathError.RelocatableSubUsizeNegOffset,
        Relocatable.new(2, 7).subFelt(Felt252.fromInteger(10)),
    );
}

test "Relocatable: relocateAddress should return an error if relocatable segment index is negative (temp segment)" {
    var relocation_table = [_]usize{ 1, 2, 3, 4 };
    try expectError(
        MemoryError.TemporarySegmentInRelocation,
        Relocatable.new(-2, 7).relocateAddress(&relocation_table),
    );
}

test "Relocatable: relocateAddress should return an error relocation table length is less than segment index" {
    var relocation_table = [_]usize{ 1, 2, 3, 4 };
    try expectError(
        MemoryError.Relocation,
        Relocatable.new(5, 7).relocateAddress(&relocation_table),
    );
}

test "Relocatable: relocateAddress should return an error relocation table length is equal to segment index" {
    var relocation_table = [_]usize{ 1, 2, 3, 4 };
    try expectError(
        MemoryError.Relocation,
        Relocatable.new(4, 7).relocateAddress(&relocation_table),
    );
}

test "Relocatable: relocateAddress should return a proper usize to relocate the address" {
    var relocation_table = [_]usize{ 1, 2, 3, 4 };
    try expectEqual(
        @as(usize, 11),
        try Relocatable.new(3, 7).relocateAddress(&relocation_table),
    );
}

test "MaybeRelocatable: eq should return true if two MaybeRelocatable are the same (Relocatable)" {
    const maybeRelocatable1 = MaybeRelocatable.fromSegment(0, 10);
    const maybeRelocatable2 = MaybeRelocatable.fromSegment(0, 10);
    try expect(maybeRelocatable1.eq(maybeRelocatable2));
}

test "MaybeRelocatable: eq should return true if two MaybeRelocatable are the same (Felt)" {
    const maybeRelocatable1 = MaybeRelocatable.fromU256(10);
    const maybeRelocatable2 = MaybeRelocatable.fromU256(10);
    try expect(maybeRelocatable1.eq(maybeRelocatable2));
}

test "MaybeRelocatable: eq should return false if two MaybeRelocatable are not the same " {
    const maybeRelocatable1 = MaybeRelocatable.fromSegment(0, 10);
    const maybeRelocatable2 = MaybeRelocatable.fromSegment(1, 10);
    const maybeRelocatable3 = MaybeRelocatable.fromU256(10);
    const maybeRelocatable4 = MaybeRelocatable.fromU256(100);
    try expect(!maybeRelocatable1.eq(maybeRelocatable2));
    try expect(!maybeRelocatable1.eq(maybeRelocatable3));
    try expect(!maybeRelocatable3.eq(maybeRelocatable2));
    try expect(!maybeRelocatable3.eq(maybeRelocatable4));
}

test "MaybeRelocatable: lt should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(!MaybeRelocatable.fromSegment(2, 4).lt(MaybeRelocatable.fromSegment(2, 4)));

    // 1 < 2
    try expect(MaybeRelocatable.fromSegment(-1, 2).lt(MaybeRelocatable.fromSegment(-1, 3)));
    try expect(MaybeRelocatable.fromSegment(1, 5).lt(MaybeRelocatable.fromSegment(2, 4)));

    // 1 > 2
    try expect(!MaybeRelocatable.fromSegment(2, 5).lt(MaybeRelocatable.fromSegment(2, 4)));
    try expect(!MaybeRelocatable.fromSegment(3, 3).lt(MaybeRelocatable.fromSegment(2, 4)));
}

test "MaybeRelocatable: le should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(MaybeRelocatable.fromSegment(2, 4).le(MaybeRelocatable.fromSegment(2, 4)));

    // 1 < 2
    try expect(MaybeRelocatable.fromSegment(-1, 2).le(MaybeRelocatable.fromSegment(-1, 3)));
    try expect(MaybeRelocatable.fromSegment(1, 5).le(MaybeRelocatable.fromSegment(2, 4)));

    // 1 > 2
    try expect(!MaybeRelocatable.fromSegment(2, 5).le(MaybeRelocatable.fromSegment(2, 4)));
    try expect(!MaybeRelocatable.fromSegment(3, 3).le(MaybeRelocatable.fromSegment(2, 4)));
}

test "MaybeRelocatable: gt should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(!MaybeRelocatable.fromSegment(2, 4).gt(MaybeRelocatable.fromSegment(2, 4)));

    // 1 < 2
    try expect(!MaybeRelocatable.fromSegment(-1, 2).gt(MaybeRelocatable.fromSegment(-1, 3)));
    try expect(!MaybeRelocatable.fromSegment(1, 5).gt(MaybeRelocatable.fromSegment(2, 4)));

    // 1 > 2
    try expect(MaybeRelocatable.fromSegment(2, 5).gt(MaybeRelocatable.fromSegment(2, 4)));
    try expect(MaybeRelocatable.fromSegment(3, 3).gt(MaybeRelocatable.fromSegment(2, 4)));
}

test "MaybeRelocatable: ge should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(MaybeRelocatable.fromSegment(2, 4).ge(MaybeRelocatable.fromSegment(2, 4)));

    // 1 < 2
    try expect(!MaybeRelocatable.fromSegment(-1, 2).ge(MaybeRelocatable.fromSegment(-1, 3)));
    try expect(!MaybeRelocatable.fromSegment(1, 5).ge(MaybeRelocatable.fromSegment(2, 4)));

    // 1 > 2
    try expect(MaybeRelocatable.fromSegment(2, 5).ge(MaybeRelocatable.fromSegment(2, 4)));
    try expect(MaybeRelocatable.fromSegment(3, 3).ge(MaybeRelocatable.fromSegment(2, 4)));
}

test "MaybeRelocatable: lt should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(!MaybeRelocatable.fromU256(1).lt(MaybeRelocatable.fromU256(1)));

    // 1 < 2
    try expect(MaybeRelocatable.fromU256(1).lt(MaybeRelocatable.fromU256(2)));

    // 1 > 2
    try expect(!MaybeRelocatable.fromU256(2).lt(MaybeRelocatable.fromU256(1)));
}

test "MaybeRelocatable: le should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(MaybeRelocatable.fromU256(1).le(MaybeRelocatable.fromU256(1)));

    // 1 < 2
    try expect(MaybeRelocatable.fromU256(1).le(MaybeRelocatable.fromU256(2)));

    // 1 > 2
    try expect(!MaybeRelocatable.fromU256(2).le(MaybeRelocatable.fromU256(1)));
}

test "MaybeRelocatable: gt should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(!MaybeRelocatable.fromU256(1).gt(MaybeRelocatable.fromU256(1)));

    // 1 < 2
    try expect(!MaybeRelocatable.fromU256(1).gt(MaybeRelocatable.fromU256(2)));

    // 1 > 2
    try expect(MaybeRelocatable.fromU256(2).gt(MaybeRelocatable.fromU256(1)));
}

test "MaybeRelocatable: ge should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(MaybeRelocatable.fromU256(1).ge(MaybeRelocatable.fromU256(1)));

    // 1 < 2
    try expect(!MaybeRelocatable.fromU256(1).ge(MaybeRelocatable.fromU256(2)));

    // 1 > 2
    try expect(MaybeRelocatable.fromU256(2).ge(MaybeRelocatable.fromU256(1)));
}

test "MaybeRelocatable: cmp should return proper order results for Relocatable comparisons" {
    try expectEqual(
        std.math.Order.eq,
        MaybeRelocatable.fromSegment(4, 10).cmp(MaybeRelocatable.fromSegment(4, 10)),
    );
    try expectEqual(
        std.math.Order.lt,
        MaybeRelocatable.fromSegment(4, 5).cmp(MaybeRelocatable.fromSegment(4, 10)),
    );
    try expectEqual(
        std.math.Order.gt,
        MaybeRelocatable.fromSegment(4, 15).cmp(MaybeRelocatable.fromSegment(4, 10)),
    );
    try expectEqual(
        std.math.Order.lt,
        MaybeRelocatable.fromSegment(2, 15).cmp(MaybeRelocatable.fromSegment(4, 10)),
    );
    try expectEqual(
        std.math.Order.gt,
        MaybeRelocatable.fromSegment(20, 15).cmp(MaybeRelocatable.fromSegment(4, 10)),
    );
}

test "MaybeRelocatable: cmp should return Felt252 > Relocatable" {
    try expectEqual(
        std.math.Order.lt,
        MaybeRelocatable.fromSegment(4, 10).cmp(MaybeRelocatable.fromU256(4)),
    );
    try expectEqual(
        std.math.Order.gt,
        MaybeRelocatable.fromU256(4).cmp(MaybeRelocatable.fromSegment(4, 10)),
    );
}

test "MaybeRelocatable: cmp should return proper order results for Felt252 comparisons" {
    try expectEqual(
        std.math.Order.lt,
        MaybeRelocatable.fromU256(10).cmp(MaybeRelocatable.fromU256(343535)),
    );
    try expectEqual(
        std.math.Order.lt,
        MaybeRelocatable.fromU256(433).cmp(MaybeRelocatable.fromU256(343535)),
    );
    try expectEqual(
        std.math.Order.gt,
        MaybeRelocatable.fromU256(543636535).cmp(MaybeRelocatable.fromU256(434)),
    );
    try expectEqual(
        std.math.Order.gt,
        MaybeRelocatable.fromU256(std.math.maxInt(u256)).cmp(MaybeRelocatable.fromU256(21313)),
    );
    try expectEqual(
        std.math.Order.eq,
        MaybeRelocatable.fromU256(10).cmp(MaybeRelocatable.fromU256(10)),
    );
    try expectEqual(
        std.math.Order.eq,
        MaybeRelocatable.fromU256(1).cmp(MaybeRelocatable.fromU256(1)),
    );
    try expectEqual(
        std.math.Order.eq,
        MaybeRelocatable.fromU256(0).cmp(MaybeRelocatable.fromU256(0)),
    );
    try expectEqual(
        std.math.Order.eq,
        MaybeRelocatable.fromU256(10).cmp(MaybeRelocatable.fromU256(10 + 0x800000000000011000000000000000000000000000000000000000000000001)),
    );
}

test "MaybeRelocatable: tryIntoRelocatable should return Relocatable if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = MaybeRelocatable.fromSegment(0, 10);
    try expectEqual(
        Relocatable.new(0, 10),
        try maybeRelocatable.tryIntoRelocatable(),
    );
}

test "MaybeRelocatable: tryIntoRelocatable should return an error if MaybeRelocatable is Felt" {
    var maybeRelocatable = MaybeRelocatable.fromU256(10);
    try expectError(
        CairoVMError.TypeMismatchNotRelocatable,
        maybeRelocatable.tryIntoRelocatable(),
    );
}

test "MaybeRelocatable: isZero should return false if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = MaybeRelocatable.fromSegment(0, 10);
    try expect(!maybeRelocatable.isZero());
}

test "MaybeRelocatable: isZero should return false if MaybeRelocatable is non Zero felt" {
    var maybeRelocatable = MaybeRelocatable.fromU256(10);
    try expect(!maybeRelocatable.isZero());
}

test "MaybeRelocatable: isZero should return true if MaybeRelocatable is Zero felt" {
    var maybeRelocatable = MaybeRelocatable.fromU256(0);
    try expect(maybeRelocatable.isZero());
}

test "MaybeRelocatable: isRelocatable should return true if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = MaybeRelocatable.fromSegment(0, 10);
    try expect(maybeRelocatable.isRelocatable());
}

test "MaybeRelocatable: isRelocatable should return false if MaybeRelocatable is felt" {
    var maybeRelocatable = MaybeRelocatable.fromU256(10);
    try expect(!maybeRelocatable.isRelocatable());
}

test "MaybeRelocatable: isFelt should return true if MaybeRelocatable is Felt" {
    var maybeRelocatable = MaybeRelocatable.fromU256(10);
    try expect(maybeRelocatable.isFelt());
}

test "MaybeRelocatable: isFelt should return false if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = MaybeRelocatable.fromSegment(0, 10);
    try expect(!maybeRelocatable.isFelt());
}

test "MaybeRelocatable: tryIntoFelt should return Felt if MaybeRelocatable is Felt" {
    var maybeRelocatable = MaybeRelocatable.fromU256(10);
    try expectEqual(Felt252.fromInteger(10), try maybeRelocatable.tryIntoFelt());
}

test "MaybeRelocatable: tryIntoFelt should return an error if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = MaybeRelocatable.fromSegment(0, 10);
    try expectError(CairoVMError.TypeMismatchNotFelt, maybeRelocatable.tryIntoFelt());
}

test "MaybeRelocatable: tryIntoU64 should return a u64 if MaybeRelocatable is Felt" {
    var maybeRelocatable = MaybeRelocatable.fromU256(10);
    try expectEqual(@as(u64, @intCast(10)), try maybeRelocatable.tryIntoU64());
}

test "MaybeRelocatable: tryIntoU64 should return an error if MaybeRelocatable is Relocatable" {
    const maybeRelocatable = MaybeRelocatable.fromSegment(0, 10);
    try expectError(CairoVMError.TypeMismatchNotFelt, maybeRelocatable.tryIntoU64());
}

test "MaybeRelocatable: tryIntoU64 should return an error if MaybeRelocatable Felt cannot be coerced to u64" {
    var maybeRelocatable = MaybeRelocatable.fromU256(std.math.maxInt(u64) + 1);
    try expectError(MathError.ValueTooLarge, maybeRelocatable.tryIntoU64());
}

test "MaybeRelocatable: any comparision should return false if other MaybeRelocatable is of different variant 1" {
    const maybeRelocatable1 = MaybeRelocatable.fromSegment(0, 10);
    const maybeRelocatable2 = MaybeRelocatable.fromU256(10);

    try expect(!maybeRelocatable1.lt(maybeRelocatable2));
    try expect(!maybeRelocatable1.le(maybeRelocatable2));
    try expect(!maybeRelocatable1.gt(maybeRelocatable2));
    try expect(!maybeRelocatable1.ge(maybeRelocatable2));
}

test "MaybeRelocatable: any comparision should return false if other MaybeRelocatable is of different variant 2" {
    const maybeRelocatable1 = MaybeRelocatable.fromU256(10);
    const maybeRelocatable2 = MaybeRelocatable.fromSegment(0, 10);

    try expect(!maybeRelocatable1.lt(maybeRelocatable2));
    try expect(!maybeRelocatable1.le(maybeRelocatable2));
    try expect(!maybeRelocatable1.gt(maybeRelocatable2));
    try expect(!maybeRelocatable1.ge(maybeRelocatable2));
}

test "MaybeRelocatable: add between two relocatable should return a Math error" {
    try expectError(
        MathError.RelocatableAdd,
        MaybeRelocatable.fromSegment(0, 10).add(MaybeRelocatable.fromSegment(0, 10)),
    );
}

test "MaybeRelocatable: add between a Relocatable and a Felt252 should return a proper MaybeRelocatable" {
    try expectEqual(
        MaybeRelocatable.fromSegment(0, 20),
        try MaybeRelocatable.fromSegment(0, 10).add(MaybeRelocatable.fromU256(10)),
    );
}

test "MaybeRelocatable: add between two Felt252 should return a proper MaybeRelocatable" {
    try expectEqual(
        MaybeRelocatable.fromU256(20),
        try MaybeRelocatable.fromU256(10).add(MaybeRelocatable.fromU256(10)),
    );
}

test "MaybeRelocatable: add between a Felt252 and a Relocatable should return a proper MaybeRelocatable" {
    try expectEqual(
        MaybeRelocatable.fromSegment(0, 20),
        try MaybeRelocatable.fromU256(10).add(MaybeRelocatable.fromSegment(0, 10)),
    );
}

test "MaybeRelocatable: sub between two Relocatable should return a proper MaybeRelocatable" {
    try expectEqual(
        MaybeRelocatable.fromSegment(0, 10),
        try MaybeRelocatable.fromSegment(0, 20).sub(MaybeRelocatable.fromSegment(0, 10)),
    );
}

test "MaybeRelocatable: sub between two Relocatable with different segment indexes should return an error" {
    try expectError(
        CairoVMError.TypeMismatchNotRelocatable,
        MaybeRelocatable.fromSegment(3, 20).sub(MaybeRelocatable.fromSegment(0, 10)),
    );
}

test "MaybeRelocatable: sub between a Relocatable and a Felt252 should return a proper MaybeRelocatable" {
    try expectEqual(
        MaybeRelocatable.fromSegment(0, 10),
        try MaybeRelocatable.fromSegment(0, 20).sub(MaybeRelocatable.fromU256(10)),
    );
}

test "MaybeRelocatable: sub between two Felt252 should return a proper MaybeRelocatable" {
    try expectEqual(
        MaybeRelocatable.fromU256(0),
        try MaybeRelocatable.fromU256(20).sub(MaybeRelocatable.fromU256(20)),
    );
}

test "MaybeRelocatable: sub between a Felt252 and a Relocatable should return a Math Error" {
    try expectError(
        MathError.SubRelocatableFromInt,
        MaybeRelocatable.fromU256(20).sub(MaybeRelocatable.fromSegment(0, 10)),
    );
}

test "MaybeRelocatable: relocateValue should return Felt252 if self argument is Felt252" {
    var relocation_table = [_]usize{ 1, 2, 3, 4 };
    var mr = MaybeRelocatable.fromU256(10);
    try expectEqual(
        Felt252.fromInteger(10),
        try mr.relocateValue(&relocation_table),
    );
}

test "MaybeRelocatable: relocateValue with a relocatable value" {
    var relocation_table = [_]usize{ 1, 2, 5 };
    var mr = MaybeRelocatable.fromSegment(2, 7);
    try expectEqual(
        Felt252.fromInteger(12),
        try mr.relocateValue(&relocation_table),
    );
}

test "MaybeRelocatable: relocateValue with a temporary segment value" {
    var relocation_table = [_]usize{ 1, 2, 5 };
    var mr = MaybeRelocatable.fromSegment(-1, 7);
    try expectError(
        MemoryError.TemporarySegmentInRelocation,
        mr.relocateValue(&relocation_table),
    );
}

test "MaybeRelocatable: relocateValue with index out of bounds" {
    var relocation_table = [_]usize{ 1, 2 };
    var mr = MaybeRelocatable.fromSegment(2, 7);
    try expectError(
        MemoryError.Relocation,
        mr.relocateValue(&relocation_table),
    );
}

test "fromRelocatable: should create a MaybeRelocatable from a Relocatable" {
    try expectEqual(
        MaybeRelocatable.fromSegment(0, 3),
        MaybeRelocatable.fromRelocatable(Relocatable.new(0, 3)),
    );
}

test "fromFelt: should create a MaybeRelocatable from a Felt" {
    try expectEqual(
        MaybeRelocatable.fromU256(10),
        MaybeRelocatable.fromFelt(Felt252.fromInteger(10)),
    );
}

test "MaybeRelocatable.fromU256: should create a MaybeRelocatable from a u256" {
    try expectEqual(
        MaybeRelocatable.fromU256(1000000),
        MaybeRelocatable.fromU256(@intCast(1000000)),
    );
}

test "MaybeRelocatable.fromU64: should create a MaybeRelocatable from a u64" {
    try expectEqual(
        MaybeRelocatable.fromU256(45),
        MaybeRelocatable.fromU64(@intCast(45)),
    );
}
