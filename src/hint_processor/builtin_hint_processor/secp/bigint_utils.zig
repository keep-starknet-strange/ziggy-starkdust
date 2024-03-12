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
const HintProcessor = @import("../../hint_processor_def.zig").CairoVMHintProcessor;
const HintData = @import("../../hint_processor_def.zig").HintData;
const testing_utils = @import("../../testing_utils.zig");
const MemoryError = @import("../../../vm/error.zig").MemoryError;
const MaybeRelocatable = @import("../../../vm/memory/relocatable.zig").MaybeRelocatable;
const Int = @import("std").math.big.int.Managed;

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
                const new_addr = try addr.addUint(i);
                self.limbs[i] = try vm.getFelt(new_addr);
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

        pub fn split(self: *Self, num: Int) Self {
            const limbs = splitBigInt(num, 128);
            return self.fromValues(limbs);
        }

        // @TODO: implement from. It is dependent on split function.
        pub fn from(self: *Self, value: Int) !Self {
            // Assuming we have a `split` function in BigIntN.zig that performs the conversion.
            return self.split(value);
        }
    };
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

test "BigIntN Hints: get bigint3 from base address should work" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{1} },
        .{ .{ 0, 1 }, .{2} },
        .{ .{ 0, 2 }, .{3} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var x: BigInt3 = undefined;
    _ = try x.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm);

    try std.testing.expectEqual(Felt252.one(), x.limbs[0]);
    try std.testing.expectEqual(Felt252.two(), x.limbs[1]);
    try std.testing.expectEqual(Felt252.three(), x.limbs[2]);
}

test "BigIntN Hints: get Bigint5 from base address should work" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{1} },
        .{ .{ 0, 1 }, .{2} },
        .{ .{ 0, 2 }, .{3} },
        .{ .{ 0, 3 }, .{4} },
        .{ .{ 0, 4 }, .{5} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var x: BigInt5 = undefined;
    _ = try x.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm);

    try std.testing.expectEqual(Felt252.one(), x.limbs[0]);
    try std.testing.expectEqual(Felt252.two(), x.limbs[1]);
    try std.testing.expectEqual(Felt252.three(), x.limbs[2]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 4), x.limbs[3]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 5), x.limbs[4]);
}

test "Get BigInt3 from base address with missing member should fail" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{1} },
        .{ .{ 0, 1 }, .{2} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var x: BigInt3 = undefined;

    try std.testing.expectError(MemoryError.UnknownMemoryCell, x.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm));
}

test "Get BigInt5 from base address with missing member should fail" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{1} },
        .{ .{ 0, 1 }, .{2} },
        .{ .{ 0, 2 }, .{3} },
        .{ .{ 0, 3 }, .{4} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var x: BigInt5 = undefined;

    try std.testing.expectError(MemoryError.UnknownMemoryCell, x.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm));
}

test "BigIntN Hints: get bigint3 from var name should work" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
    });

    // defer vm.segments.memory.deinitData(std.testing.allocator);

    // var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{.{
    //     .name = "x",
    //     .elems = &.{MaybeRelocatable.fromRelocatable(Relocatable{ .segment_index = 1, .offset = 0 })},
    // }}, &vm);

    // var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{.{ .name = "x", .elems = &.{MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 0))} }}, &vm);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"x"});
    defer ids_data.deinit();

    var x: BigInt3 = undefined;
    _ = try x.fromVarName("x", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.one(), x.limbs[0]);
    // try std.testing.expectEqual(Felt252.two(), x.limbs[1]);
    // try std.testing.expectEqual(Felt252.three(), x.limbs[2]);
}
