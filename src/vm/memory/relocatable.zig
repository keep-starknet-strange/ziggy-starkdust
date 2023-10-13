const std = @import("std");
const starknet_felt = @import("../../math/fields/starknet.zig");
const CairoVMError = @import("../error.zig").CairoVMError;

// Relocatable in the Cairo VM represents an address
// in some memory segment. When the VM finishes running,
// these values are replaced by real memory addresses,
// represented by a field element.
pub const Relocatable = struct {
    // The index of the memory segment.
    segment_index: u64,
    // The offset in the memory segment.
    offset: u64,

    // Creates a new Relocatable with the default values.
    // # Returns
    // A new Relocatable with the default values.
    pub fn default() Relocatable {
        return Relocatable{
            .segment_index = 0,
            .offset = 0,
        };
    }

    // Creates a new Relocatable.
    // # Arguments
    // - segment_index - The index of the memory segment.
    // - offset - The offset in the memory segment.
    // # Returns
    // A new Relocatable.
    pub fn new(segment_index: u64, offset: u64) Relocatable {
        return Relocatable{
            .segment_index = segment_index,
            .offset = offset,
        };
    }

    // Determines if this Relocatable is equal to another.
    // # Arguments
    // - other: The other Relocatable to compare to.
    // # Returns
    // `true` if they are equal, `false` otherwise.
    pub fn eq(self: Relocatable, other: Relocatable) bool {
        return self.segment_index == other.segment_index and self.offset == other.offset;
    }

    // Substract a u64 from a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The u64 to substract.
    // # Returns
    // A new Relocatable.
    pub fn subUint(self: Relocatable, other: u64) !Relocatable {
        if (self.offset < other) {
            return error.RelocatableSubUsizeNegOffset;
        }
        return Relocatable{
            .segment_index = self.segment_index,
            .offset = self.offset - other,
        };
    }

    // Add a u64 to a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The u64 to add.
    // # Returns
    // A new Relocatable.
    pub fn addUint(self: Relocatable, other: u64) !Relocatable {
        return Relocatable{
            .segment_index = self.segment_index,
            .offset = self.offset + other,
        };
    }

    // Add a i64 to a Relocatable and return a new Relocatable.
    // # Arguments
    // - other: The i64 to add.
    // # Returns
    // A new Relocatable.
    pub fn addInt(self: Relocatable, other: i64) !Relocatable {
        if (other < 0) {
            return self.subUint(@as(u64, @intCast(-other)));
        }
        return self.addUint(@as(u64, @intCast(other)));
    }
};

// MaybeRelocatable is the type of the memory cells in the Cairo
// VM. It can either be a Relocatable or a field element.
pub const MaybeRelocatable = union(enum) {
    relocatable: Relocatable,
    felt: starknet_felt.Felt252,

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
    pub fn eq(self: MaybeRelocatable, other: MaybeRelocatable) bool {
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

    // Return the value of the MaybeRelocatable as a felt or error.
    // # Returns
    // The value of the MaybeRelocatable as a Relocatable felt or error.
    pub fn tryIntoFelt(self: MaybeRelocatable) error{TypeMismatchNotFelt}!starknet_felt.Felt252 {
        return switch (self) {
            .relocatable => CairoVMError.TypeMismatchNotFelt,
            .felt => |felt| felt,
        };
    }

    // Return the value of the MaybeRelocatable as a felt or error.
    // # Returns
    // The value of the MaybeRelocatable as a Relocatable felt or error.
    pub fn tryIntoU64(self: MaybeRelocatable) error{ TypeMismatchNotFelt, ValueTooLarge }!u64 {
        return switch (self) {
            .relocatable => CairoVMError.TypeMismatchNotFelt,
            .felt => |felt| felt.tryIntoU64(),
        };
    }

    // Return the value of the MaybeRelocatable as a Relocatable.
    // # Returns
    // The value of the MaybeRelocatable as a Relocatable.
    pub fn tryIntoRelocatable(self: MaybeRelocatable) !Relocatable {
        return switch (self) {
            .relocatable => |relocatable| relocatable,
            .felt => error.TypeMismatchNotRelocatable,
        };
    }
};

// Creates a new MaybeRelocatable from a Relocatable.
// # Arguments
// - relocatable - The Relocatable to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn newFromRelocatable(relocatable: Relocatable) MaybeRelocatable {
    return MaybeRelocatable{ .relocatable = relocatable };
}

// Creates a new MaybeRelocatable from a field element.
// # Arguments
// - felt - The field element to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn fromFelt(felt: starknet_felt.Felt252) MaybeRelocatable {
    return MaybeRelocatable{ .felt = felt };
}

// Creates a new MaybeRelocatable from a u256.
// # Arguments
// - value - The u64 to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn fromU256(value: u256) MaybeRelocatable {
    return MaybeRelocatable{ .felt = starknet_felt.Felt252.fromInteger(value) };
}

// Creates a new MaybeRelocatable from a u64.
// # Arguments
// - value - The u64 to create the MaybeRelocatable from.
// # Returns
// A new MaybeRelocatable.
pub fn fromU64(value: u64) MaybeRelocatable {
    return fromU256(@as(u256, value));
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "add uint" {
    const relocatable = Relocatable.new(2, 4);
    const result = relocatable.addUint(24);
    const expected = Relocatable.new(2, 28);
    try expectEqual(result, expected);
}

test "add int" {
    const relocatable = Relocatable.new(2, 4);
    const result = relocatable.addInt(24);
    const expected = Relocatable.new(2, 28);
    try expectEqual(result, expected);
}

test "add int negative" {
    const relocatable = Relocatable.new(2, 4);
    const result = relocatable.addInt(-4);
    const expected = Relocatable.new(2, 0);
    try expectEqual(result, expected);
}

test "sub uint" {
    const relocatable = Relocatable.new(2, 4);
    const result = relocatable.subUint(2);
    const expected = Relocatable.new(2, 2);
    try expectEqual(result, expected);
}

test "sub uint negative" {
    const relocatable = Relocatable.new(2, 4);
    const result = relocatable.subUint(6);
    try expectError(error.RelocatableSubUsizeNegOffset, result);
}
