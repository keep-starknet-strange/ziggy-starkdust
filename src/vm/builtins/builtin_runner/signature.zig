const std = @import("std");
const Signature = @import("../../../math/crypto/signatures.zig").Signature;
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const ecdsa_instance_def = @import("../../types/ecdsa_instance_def.zig");

const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

pub const SignatureBuiltinRunner = struct {
    const Self = @This();

    included: bool,
    ratio: ?u32,
    base: usize,
    cells_per_instance: u32,
    n_input_cells: u32,
    _total_n_bits: u32,
    stop_ptr: ?usize,
    instances_per_component: u32,
    signatures: AutoHashMap(relocatable.Relocatable, Signature),

    pub fn new(allocator: Allocator, instance_def: *ecdsa_instance_def.EcdsaInstanceDef, included: bool) Self {
        return .{
            .included = included,
            .ratio = instance_def.ratio,
            .base = 0,
            .cell_per_instance = 2,
            .n_input_cells = 2,
            ._total_n_bits = 251,
            .stop_ptr = null,
            .instances_per_component = 1,
            .signatures = AutoHashMap(relocatable.Relocatable, Signature).init(allocator),
        };
    }

    pub fn get_base(self: *Self) usize {
        return self.base;
    }
};
