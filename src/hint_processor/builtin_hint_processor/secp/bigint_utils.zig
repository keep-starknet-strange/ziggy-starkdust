const std = @import("std");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const Relocatable = @import("../../../vm/memory/relocatable.zig").Relocatable;
const CairoVM = @import("../../../vm/core.zig").CairoVM;
const HintError = @import("../../../vm/error.zig").HintError;
const hint_utils = @import("../../hint_utils.zig");
const HintReference = @import("../../hint_processor_def.zig").HintReference;
const ApTracking = @import("../../../vm/types/programjson.zig").ApTracking;
const ExecutionScopes = @import("../../../vm/types/execution_scopes.zig").ExecutionScopes;
const pow2ConstNz = @import("../../math_hints.zig").pow2ConstNz;
const packBigInt = @import("../../uint_utils.zig").pack;
const splitBigInt = @import("../../uint_utils.zig").split;

pub const BigInt3 = BigIntN(3);
pub const Uint384 = BigIntN(3);
pub const Uint512 = BigIntN(4);
pub const BigInt5 = BigIntN(5);
pub const Uint768 = BigIntN(6);

pub fn BigIntN(comptime NUM_LIMBS: usize) type {
    return struct {
        const Self = @This();

        limbs: [NUM_LIMBS]Felt252 = undefined,

        pub fn fromBaseAddr(self: *Self, addr: Relocatable, vm: *CairoVM) !Self {
            inline for (0..NUM_LIMBS) |i| {
                self.limbs[i] = vm.getFelt(addr + i) catch return HintError.IdentifierHasNoMember;
            }
            return .{ .limbs = self.limbs };
        }

        pub fn fromVarName(self: *Self, name: []const u8, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !Self {
            const baseAddress = try hint_utils.getRelocatableFromVarName(name, vm, ids_data, ap_tracking);
            return self.fromBaseAddr(baseAddress, vm);
        }

        pub fn fromValues(limbs: [NUM_LIMBS]Felt252) !Self {
            return .{ .limbs = limbs };
        }

        pub fn insertFromVarName(self: *Self, allocator: std.mem.allocator, var_name: []const u8, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
            const addr = try hint_utils.getRelocatableFromVarName(var_name, vm, ids_data, ap_tracking);
            inline for (0..NUM_LIMBS) |i| {
                try vm.insertInMemory(allocator, addr + i, self.limbs[i]);
            }
        }

        pub fn pack(self: *Self) u256 {
            const result = packBigInt(self.limbs, 128);
            return result;
        }

        pub fn pack86(self: *Self) Felt252 {
            var result = Felt252.zero();
            inline for (0..NUM_LIMBS) |i| {
                result = result + (self.limbs[i] << (i * 86));
            }

            return result;
        }

        pub fn split(self: *Self, num: *std.big.Int) Self {
            const limbs = splitBigInt(num, 128);
            return self.fromValues(limbs);
        }
    };
}

// @TODO: implement fromBigUint. It is dependent on split function.
pub fn fromBigUint(value: *std.big.Int, numLimbs: usize) BigIntN {
    // Assuming we have a `split` function in BigIntN.zig that performs the conversion.
    return BigIntN.split(value, numLimbs);
}

// @TODO: implement nondetBigInt3 function
// pub fn nondetBigInt3(vm: *CairoVM, exec_scopes: *ExecutionScopes, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
//     // const res_reloc = try hint_utils.getRelocatableFromVarName("res", vm, ids_data, ap_tracking);
//     // const value = try exec_scopes.getRef("value") catch return HintError.IdentifierHasNoMember;

// }

// Implements hint
// %{ ids.low = (ids.x.d0 + ids.x.d1 * ids.BASE) & ((1 << 128) - 1) %}
pub fn bigintToUint256(vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking, constants: std.StringHashMap(Felt252)) !void {
    const x_struct = try hint_utils.getRelocatableFromVarName("x", vm, ids_data, ap_tracking);
    const d0 = try vm.getFelt(x_struct);
    const d1 = try vm.getFelt(x_struct.offset(1));
    const base_86 = constants.get("BASE_86") orelse return HintError.MissingConstant;
    const mask = pow2ConstNz(128);
    const low = ((d0 + (d1 * base_86)) % mask);
    try hint_utils.insertValueFromVarName(std.mem.Allocator, "low", low, vm, ids_data, ap_tracking);
}

// Implements hint
// %{ ids.len_hi = max(ids.scalar_u.d2.bit_length(), ids.scalar_v.d2.bit_length())-1 %}
pub fn hiMaxBitlen(vm: *CairoVM, ids_data: *std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const scalar_u = try BigInt3.fromVarName("scalar_u", vm, ids_data, ap_tracking);
    const scalar_v = try BigInt3.fromVarName("scalar_v", vm, ids_data, ap_tracking);

    // get number of bits in the highest limb
    const len_hi_u = scalar_u.limbs[2].numBits();
    const len_hi_v = scalar_v.limbs[2].numBits();

    const len_hi = std.math.max(len_hi_u, len_hi_v);

    // equal to `len_hi.wrapping_sub(1)`
    const res = if (len_hi == 0) Felt252.Max else len_hi - 1;

    try hint_utils.insertValueFromVarName("len_hi", res, vm, ids_data, ap_tracking);
}

// Tests
