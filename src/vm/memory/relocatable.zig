const std = @import("std");
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const CairoVMError = @import("../error.zig").CairoVMError;

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
    pub fn new(
        segment_index: i64,
        offset: u64,
    ) Self {
        return .{
            .segment_index = segment_index,
            .offset = offset,
        };
    }

    // Determines if this Relocatable is equal to another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if they are equal, `false` otherwise.
    pub fn eq(
        self: Self,
        other: Self,
    ) bool {
        return self.segment_index == other.segment_index and self.offset == other.offset;
    }

    // Determines if this Relocatable is less than another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is less than other, `false` otherwise.
    pub fn lt(
        self: Self,
        other: Self,
    ) bool {
        return self.segment_index < other.segment_index or (self.segment_index == other.segment_index and self.offset < other.offset);
    }

    // Determines if this Relocatable is less than or equal to another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is less than or equal to other, `false` otherwise.
    pub fn le(
        self: Self,
        other: Self,
    ) bool {
        return self.segment_index < other.segment_index or (self.segment_index == other.segment_index and self.offset <= other.offset);
    }

    // Determines if this Relocatable is greater than another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is greater than other, `false` otherwise.
    pub fn gt(
        self: Self,
        other: Self,
    ) bool {
        return self.segment_index > other.segment_index or (self.segment_index == other.segment_index and self.offset > other.offset);
    }

    // Determines if this Relocatable is greater than or equal to another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if self is greater than or equal to other, `false` otherwise.
    pub fn ge(
        self: Self,
        other: Self,
    ) bool {
        return self.segment_index > other.segment_index or (self.segment_index == other.segment_index and self.offset >= other.offset);
    }

    /// Attempts to subtract a `Relocatable` from another.
    ///
    /// This method fails if `self` and other` are not from the same segment.
    pub fn sub(self: Relocatable, other: Relocatable) !Relocatable {
        if (self.segment_index != other.segment_index) {
            return error.TypeMismatchNotRelocatable;
        }

        return try subUint(self, other.offset);
    }

    // Substract a u64 from a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The u64 to substract.
    // # Returns
    // A new Relocatable.
    pub fn subUint(
        self: Self,
        other: u64,
    ) !Self {
        if (self.offset < other) {
            return error.RelocatableSubUsizeNegOffset;
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
    pub fn addUint(
        self: Self,
        other: u64,
    ) !Self {
        return .{
            .segment_index = self.segment_index,
            .offset = self.offset + other,
        };
    }

    /// Add a u64 to this Relocatable, modifying it in place.
    /// # Arguments
    /// - self: Pointer to the Relocatable object to modify.
    /// - other: The u64 to add to `self.offset`.
    pub fn addUintInPlace(
        self: *Self,
        other: u64,
    ) void {
        // Modify the offset of the existing Relocatable object
        self.offset += other;
    }

    // Add a i64 to a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The i64 to add.
    // # Returns
    // A new Relocatable.
    pub fn addInt(
        self: Self,
        other: i64,
    ) !Self {
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

    /// Add a felt to this Relocatable, modifying it in place.
    /// # Arguments
    /// - self: Pointer to the Relocatable object to modify.
    /// - other: The felt to add to `self.offset`.
    pub fn addFeltInPlace(
        self: *Self,
        other: Felt252,
    ) !void {
        self.offset = try Felt252.fromInteger(@intCast(self.offset)).add(other).tryIntoU64();
    }

    /// Performs additions if other contains a Felt value, fails otherwise.
    /// # Arguments
    /// - other - The other MaybeRelocatable to add.
    pub fn addMaybeRelocatableInplace(
        self: *Self,
        other: MaybeRelocatable,
    ) !void {
        try self.addFeltInPlace(try other.tryIntoFelt());
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
    pub fn eq(
        self: Self,
        other: Self,
    ) bool {
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
    pub fn lt(
        self: Self,
        other: Self,
    ) bool {
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
    pub fn le(
        self: Self,
        other: Self,
    ) bool {
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
    pub fn gt(
        self: Self,
        other: Self,
    ) bool {
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
    pub fn ge(
        self: Self,
        other: Self,
    ) bool {
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

    /// Return the value of the MaybeRelocatable as a felt or error.
    /// # Returns
    /// The value of the MaybeRelocatable as a Relocatable felt or error.
    pub fn tryIntoFelt(self: Self) error{TypeMismatchNotFelt}!Felt252 {
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
    pub fn tryIntoRelocatable(self: Self) !Relocatable {
        return switch (self) {
            .relocatable => |relocatable| relocatable,
            .felt => error.TypeMismatchNotRelocatable,
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
};

// Creates a new MaybeRelocatable from a Relocatable.
// # Arguments
// - relocatable - The Relocatable to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn newFromRelocatable(relocatable: Relocatable) MaybeRelocatable {
    return .{ .relocatable = relocatable };
}

// Creates a new MaybeRelocatable from a field element.
// # Arguments
// - felt - The field element to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn fromFelt(felt: Felt252) MaybeRelocatable {
    return .{ .felt = felt };
}

// Creates a new MaybeRelocatable from a u256.
// # Arguments
// - value - The u64 to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn fromU256(value: u256) MaybeRelocatable {
    return .{ .felt = Felt252.fromInteger(value) };
}

// Creates a new MaybeRelocatable from a u64.
// # Arguments
// - value - The u64 to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn fromU64(value: u64) MaybeRelocatable {
    return fromU256(@intCast(value));
}

// Creates a new MaybeRelocatable from a segment index and an offset.
// # Arguments
// - segment_index - The i64 for segment_index
// - offset - The u64 for offset
// # Returns
// A new MaybeRelocatable.
pub fn fromSegment(segment_index: i64, offset: u64) MaybeRelocatable {
    return newFromRelocatable(Relocatable.new(segment_index, offset));
}

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
        error.RelocatableSubUsizeNegOffset,
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
        error.RelocatableSubUsizeNegOffset,
        Relocatable.new(2, 2).sub(Relocatable.new(2, 5)),
    );
}

test "Relocatable: sub two Relocatable with different segment index" {
    try expectError(
        error.TypeMismatchNotRelocatable,
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

test "MaybeRelocatable: eq should return true if two MaybeRelocatable are the same (Relocatable)" {
    var maybeRelocatable1 = fromSegment(0, 10);
    var maybeRelocatable2 = fromSegment(0, 10);
    try expect(maybeRelocatable1.eq(maybeRelocatable2));
}

test "MaybeRelocatable: eq should return true if two MaybeRelocatable are the same (Felt)" {
    var maybeRelocatable1 = fromU256(10);
    var maybeRelocatable2 = fromU256(10);
    try expect(maybeRelocatable1.eq(maybeRelocatable2));
}

test "MaybeRelocatable: eq should return false if two MaybeRelocatable are not the same " {
    var maybeRelocatable1 = fromSegment(0, 10);
    var maybeRelocatable2 = fromSegment(1, 10);
    var maybeRelocatable3 = fromU256(10);
    var maybeRelocatable4 = fromU256(100);
    try expect(!maybeRelocatable1.eq(maybeRelocatable2));
    try expect(!maybeRelocatable1.eq(maybeRelocatable3));
    try expect(!maybeRelocatable3.eq(maybeRelocatable2));
    try expect(!maybeRelocatable3.eq(maybeRelocatable4));
}

test "MaybeRelocatable: lt should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(!fromSegment(2, 4).lt(fromSegment(2, 4)));

    // 1 < 2
    try expect(fromSegment(-1, 2).lt(fromSegment(-1, 3)));
    try expect(fromSegment(1, 5).lt(fromSegment(2, 4)));

    // 1 > 2
    try expect(!fromSegment(2, 5).lt(fromSegment(2, 4)));
    try expect(!fromSegment(3, 3).lt(fromSegment(2, 4)));
}

test "MaybeRelocatable: le should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(fromSegment(2, 4).le(fromSegment(2, 4)));

    // 1 < 2
    try expect(fromSegment(-1, 2).le(fromSegment(-1, 3)));
    try expect(fromSegment(1, 5).le(fromSegment(2, 4)));

    // 1 > 2
    try expect(!fromSegment(2, 5).le(fromSegment(2, 4)));
    try expect(!fromSegment(3, 3).le(fromSegment(2, 4)));
}

test "MaybeRelocatable: gt should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(!fromSegment(2, 4).gt(fromSegment(2, 4)));

    // 1 < 2
    try expect(!fromSegment(-1, 2).gt(fromSegment(-1, 3)));
    try expect(!fromSegment(1, 5).gt(fromSegment(2, 4)));

    // 1 > 2
    try expect(fromSegment(2, 5).gt(fromSegment(2, 4)));
    try expect(fromSegment(3, 3).gt(fromSegment(2, 4)));
}

test "MaybeRelocatable: ge should work properly if two MaybeRelocatable are of same type (Relocatable)" {
    // 1 == 2
    try expect(fromSegment(2, 4).ge(fromSegment(2, 4)));

    // 1 < 2
    try expect(!fromSegment(-1, 2).ge(fromSegment(-1, 3)));
    try expect(!fromSegment(1, 5).ge(fromSegment(2, 4)));

    // 1 > 2
    try expect(fromSegment(2, 5).ge(fromSegment(2, 4)));
    try expect(fromSegment(3, 3).ge(fromSegment(2, 4)));
}

test "MaybeRelocatable: lt should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(!fromU256(1).lt(fromU256(1)));

    // 1 < 2
    try expect(fromU256(1).lt(fromU256(2)));

    // 1 > 2
    try expect(!fromU256(2).lt(fromU256(1)));
}

test "MaybeRelocatable: le should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(fromU256(1).le(fromU256(1)));

    // 1 < 2
    try expect(fromU256(1).le(fromU256(2)));

    // 1 > 2
    try expect(!fromU256(2).le(fromU256(1)));
}

test "MaybeRelocatable: gt should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(!fromU256(1).gt(fromU256(1)));

    // 1 < 2
    try expect(!fromU256(1).gt(fromU256(2)));

    // 1 > 2
    try expect(fromU256(2).gt(fromU256(1)));
}

test "MaybeRelocatable: ge should work properly if two MaybeRelocatable are of same type (Felt)" {
    // 1 == 2
    try expect(fromU256(1).ge(fromU256(1)));

    // 1 < 2
    try expect(!fromU256(1).ge(fromU256(2)));

    // 1 > 2
    try expect(fromU256(2).ge(fromU256(1)));
}

test "MaybeRelocatable: tryIntoRelocatable should return Relocatable if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = fromSegment(0, 10);
    try expectEqual(
        Relocatable.new(0, 10),
        try maybeRelocatable.tryIntoRelocatable(),
    );
}

test "MaybeRelocatable: tryIntoRelocatable should return an error if MaybeRelocatable is Felt" {
    var maybeRelocatable = fromU256(10);
    try expectError(
        error.TypeMismatchNotRelocatable,
        maybeRelocatable.tryIntoRelocatable(),
    );
}

test "MaybeRelocatable: isZero should return false if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = fromSegment(0, 10);
    try expect(!maybeRelocatable.isZero());
}

test "MaybeRelocatable: isZero should return false if MaybeRelocatable is non Zero felt" {
    var maybeRelocatable = fromU256(10);
    try expect(!maybeRelocatable.isZero());
}

test "MaybeRelocatable: isZero should return true if MaybeRelocatable is Zero felt" {
    var maybeRelocatable = fromU256(0);
    try expect(maybeRelocatable.isZero());
}

test "MaybeRelocatable: isRelocatable should return true if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = fromSegment(0, 10);
    try expect(maybeRelocatable.isRelocatable());
}

test "MaybeRelocatable: isRelocatable should return false if MaybeRelocatable is felt" {
    var maybeRelocatable = fromU256(10);
    try expect(!maybeRelocatable.isRelocatable());
}

test "MaybeRelocatable: isFelt should return true if MaybeRelocatable is Felt" {
    var maybeRelocatable = fromU256(10);
    try expect(maybeRelocatable.isFelt());
}

test "MaybeRelocatable: isFelt should return false if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = fromSegment(0, 10);
    try expect(!maybeRelocatable.isFelt());
}

test "MaybeRelocatable: tryIntoFelt should return Felt if MaybeRelocatable is Felt" {
    var maybeRelocatable = fromU256(10);
    try expectEqual(Felt252.fromInteger(10), try maybeRelocatable.tryIntoFelt());
}

test "MaybeRelocatable: tryIntoFelt should return an error if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = fromSegment(0, 10);
    try expectError(CairoVMError.TypeMismatchNotFelt, maybeRelocatable.tryIntoFelt());
}

test "MaybeRelocatable: tryIntoU64 should return a u64 if MaybeRelocatable is Felt" {
    var maybeRelocatable = fromU256(10);
    try expectEqual(@as(u64, @intCast(10)), try maybeRelocatable.tryIntoU64());
}

test "MaybeRelocatable: tryIntoU64 should return an error if MaybeRelocatable is Relocatable" {
    var maybeRelocatable = fromSegment(0, 10);
    try expectError(CairoVMError.TypeMismatchNotFelt, maybeRelocatable.tryIntoU64());
}

test "MaybeRelocatable: tryIntoU64 should return an error if MaybeRelocatable Felt cannot be coerced to u64" {
    var maybeRelocatable = fromU256(std.math.maxInt(u64) + 1);
    try expectError(error.ValueTooLarge, maybeRelocatable.tryIntoU64());
}

test "MaybeRelocatable: any comparision should return false if other MaybeRelocatable is of different variant 1" {
    var maybeRelocatable1 = fromSegment(0, 10);
    var maybeRelocatable2 = fromU256(10);

    try expect(!maybeRelocatable1.lt(maybeRelocatable2));
    try expect(!maybeRelocatable1.le(maybeRelocatable2));
    try expect(!maybeRelocatable1.gt(maybeRelocatable2));
    try expect(!maybeRelocatable1.ge(maybeRelocatable2));
}

test "MaybeRelocatable: any comparision should return false if other MaybeRelocatable is of different variant 2" {
    var maybeRelocatable1 = fromU256(10);
    var maybeRelocatable2 = fromSegment(0, 10);

    try expect(!maybeRelocatable1.lt(maybeRelocatable2));
    try expect(!maybeRelocatable1.le(maybeRelocatable2));
    try expect(!maybeRelocatable1.gt(maybeRelocatable2));
    try expect(!maybeRelocatable1.ge(maybeRelocatable2));
}

test "newFromRelocatable: should create a MaybeRelocatable from a Relocatable" {
    try expectEqual(
        fromSegment(0, 3),
        newFromRelocatable(Relocatable.new(0, 3)),
    );
}

test "fromFelt: should create a MaybeRelocatable from a Felt" {
    try expectEqual(
        fromU256(10),
        fromFelt(Felt252.fromInteger(10)),
    );
}

test "fromU256: should create a MaybeRelocatable from a u256" {
    try expectEqual(
        fromU256(1000000),
        fromU256(@intCast(1000000)),
    );
}

test "fromU64: should create a MaybeRelocatable from a u64" {
    try expectEqual(
        fromU256(45),
        fromU64(@intCast(45)),
    );
}
