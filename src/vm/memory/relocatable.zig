const starknet_felt = @import("../../math/fields/starknet.zig");

// Relocatable in the Cairo VM represents an address
// in some memory segment. When the VM finishes running,
// these values are replaced by real memory addresses,
// represented by a field element.
pub const Relocatable = struct {
    // The index of the memory segment.
    segment_index: u32,
    // The offset in the memory segment.
    offset: u32,

    pub fn default() Relocatable {
        return Relocatable{
            .segment_index = 0,
            .offset = 0,
        };
    }
};

// MaybeRelocatable is the type of the memory cells in the Cairo
// VM. It can either be a Relocatable or a field element.
pub const MaybeRelocatable = union(enum) {
    relocatable: Relocatable,
    felt: starknet_felt.Felt252,
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
pub fn newFromFelt(felt: starknet_felt.Felt252) MaybeRelocatable {
    return MaybeRelocatable{ .felt = felt };
}
