// Core imports.
const std = @import("std");
const expect = @import("std").testing.expect;
const Allocator = std.mem.Allocator;

// Local imports.
const relocatable = @import("relocatable.zig");

// Representation of the VM memory.
pub const Memory = struct {
    // The data in the memory.
    data: std.HashMap(relocatable.Relocatable, relocatable.MaybeRelocatable, std.hash_map.AutoContext(relocatable.Relocatable), std.hash_map.default_max_load_percentage),
    // The number of segments in the memory.
    num_segments: u32,
    // Validated addresses are addresses that have been validated.
    // TODO: Consider merging this with `data` and benchmarking.
    validated_addresses: std.HashMap(relocatable.Relocatable, bool, std.hash_map.AutoContext(relocatable.Relocatable), std.hash_map.default_max_load_percentage),

    // Creates a new memory.
    // # Arguments
    // - `allocator` - The allocator to use.
    // # Returns
    // The new memory.
    pub fn init(allocator: Allocator) Memory {
        return Memory{
            .data = std.AutoHashMap(relocatable.Relocatable, relocatable.MaybeRelocatable).init(allocator),
            .num_segments = 0,
            .validated_addresses = std.AutoHashMap(relocatable.Relocatable, bool).init(allocator),
        };
    }
};
