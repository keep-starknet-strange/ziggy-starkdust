const std = @import("std");
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const CairoVMError = @import("../error.zig").CairoVMError;

// Relocatable in the Cairo VM represents an address
// in some memory segment. When the VM finishes running,
// these values are replaced by real memory addresses,
// represented by a field element.
pub const Relocatable = struct {
    // The index of the memory segment.
    segment_index: u64 = 0,
    // The offset in the memory segment.
    offset: u64 = 0,

    // Creates a new Relocatable.
    // # Arguments
    // - segment_index - The index of the memory segment.
    // - offset - The offset in the memory segment.
    // # Returns
    // A new Relocatable.
    pub fn new(
        segment_index: u64,
        offset: u64,
    ) Relocatable {
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
        self: Relocatable,
        other: Relocatable,
    ) bool {
        return self.segment_index == other.segment_index and self.offset == other.offset;
    }

    /// Attempts to subtract a `Relocatable` from another.
    ///
    /// This method fails if `self` and other` are not from the same segment.
    pub fn sub(self: Relocatable, other: Relocatable) !Relocatable {
        if (self.segment_index != other.segment_index) {
            return error.TypeMismatchNotRelocatable;
        }

        return subUint(self, other.offset);
    }

    // Substract a u64 from a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The u64 to substract.
    // # Returns
    // A new Relocatable.
    pub fn subUint(
        self: Relocatable,
        other: u64,
    ) !Relocatable {
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
        self: Relocatable,
        other: u64,
    ) !Relocatable {
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
        self: *Relocatable,
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
        self: Relocatable,
        other: i64,
    ) !Relocatable {
        if (other < 0) {
            return self.subUint(@as(u64, @intCast(
                -other,
            )));
        }
        return self.addUint(@as(u64, @intCast(
            other,
        )));
    }

    /// Add a felt to this Relocatable, modifying it in place.
    /// # Arguments
    /// - self: Pointer to the Relocatable object to modify.
    /// - other: The felt to add to `self.offset`.
    pub fn addFeltInPlace(
        self: *Relocatable,
        other: Felt252,
    ) !void {
        const new_offset_felt = Felt252.fromInteger(@as(
            u256,
            self.offset,
        )).add(other);
        const new_offset = try new_offset_felt.tryIntoU64();
        self.offset = new_offset;
    }

    /// Performs additions if other contains a Felt value, fails otherwise.
    /// # Arguments
    /// - other - The other MaybeRelocatable to add.
    pub fn addMaybeRelocatableInplace(
        self: *Relocatable,
        other: MaybeRelocatable,
    ) !void {
        const other_as_felt = try other.tryIntoFelt();
        try self.addFeltInPlace(other_as_felt);
    }
};

// MaybeRelocatable is the type of the memory cells in the Cairo
// VM. It can either be a Relocatable or a field element.
pub const MaybeRelocatable = union(enum) {
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
        self: MaybeRelocatable,
        other: MaybeRelocatable,
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

    /// Subtracts a `MaybeRelocatable` from this one and returns the new value.
    ///
    /// Only values of the same type may be subtracted. Specifically, attempting to
    /// subtract a `.felt` with a `.relocatable` will result in an error.
    pub fn sub(self: MaybeRelocatable, other: MaybeRelocatable) !MaybeRelocatable {
        switch (self) {
            .felt => |self_value| switch (other) {
                .felt => |other_value| return fromFelt(self_value.sub(other_value)),
                .relocatable => return error.TypeMismatchNotFelt,
            },
            .relocatable => |self_value| switch (other) {
                .felt => return error.TypeMismatchNotFelt,
                .relocatable => |other_value| return newFromRelocatable(try self_value.sub(other_value)),
            },
        }
    }

    /// Return the value of the MaybeRelocatable as a felt or error.
    /// # Returns
    /// The value of the MaybeRelocatable as a Relocatable felt or error.
    pub fn tryIntoFelt(self: MaybeRelocatable) error{TypeMismatchNotFelt}!Felt252 {
        return switch (self) {
            .relocatable => CairoVMError.TypeMismatchNotFelt,
            .felt => |felt| felt,
        };
    }

    /// Return the value of the MaybeRelocatable as a felt or error.
    /// # Returns
    /// The value of the MaybeRelocatable as a Relocatable felt or error.
    pub fn tryIntoU64(self: MaybeRelocatable) error{
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
    pub fn tryIntoRelocatable(self: MaybeRelocatable) !Relocatable {
        return switch (self) {
            .relocatable => |relocatable| relocatable,
            .felt => error.TypeMismatchNotRelocatable,
        };
    }

    /// Whether the MaybeRelocatable is zero or not.
    /// # Returns
    /// true if the MaybeRelocatable is zero, false otherwise.
    pub fn isZero(self: MaybeRelocatable) bool {
        return switch (self) {
            .relocatable => false,
            .felt => |felt| felt.isZero(),
        };
    }

    /// Whether the MaybeRelocatable is a relocatable or not.
    /// # Returns
    /// true if the MaybeRelocatable is a relocatable, false otherwise.
    pub fn isRelocatable(self: MaybeRelocatable) bool {
        return switch (self) {
            .relocatable => true,
            .felt => false,
        };
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
    return fromU256(@as(
        u256,
        value,
    ));
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "add uint" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = relocatable.addUint(24);
    const expected = Relocatable.new(
        2,
        28,
    );
    try expectEqual(
        result,
        expected,
    );
}

test "add int" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = relocatable.addInt(24);
    const expected = Relocatable.new(
        2,
        28,
    );
    try expectEqual(
        result,
        expected,
    );
}

test "add int negative" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = relocatable.addInt(-4);
    const expected = Relocatable.new(
        2,
        0,
    );
    try expectEqual(
        result,
        expected,
    );
}

test "sub uint" {
    const relocatable = Relocatable.new(
        2,
        4,
    );
    const result = relocatable.subUint(2);
    const expected = Relocatable.new(
        2,
        2,
    );
    try expectEqual(
        result,
        expected,
    );
}

test "sub uint negative" {
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
