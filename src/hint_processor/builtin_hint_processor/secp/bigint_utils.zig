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
const secp_utils = @import("../secp/secp_utils.zig");
const bigInt3Split = secp_utils.bigInt3Split;
const BigInt = std.math.big.int.Managed;
const BASE = @import("../../../math//fields/constants.zig").BASE;
const hint_codes = @import("../../builtin_hint_codes.zig");

pub const BigInt3 = BigIntN(3);
pub const Uint384 = BigIntN(3);
pub const Uint512 = BigIntN(4);
pub const BigInt5 = BigIntN(5);
pub const Uint768 = BigIntN(6);

pub fn BigIntN(comptime NUM_LIMBS: usize) type {
    return struct {
        const Self = @This();

        limbs: [NUM_LIMBS]Felt252 = undefined,

        pub fn fromBaseAddr(addr: Relocatable, vm: *CairoVM) !Self {
            var limbs: [NUM_LIMBS]Felt252 = undefined;

            inline for (0..NUM_LIMBS) |i| {
                limbs[i] = try vm.getFelt(try addr.addUint(i));
            }

            return .{ .limbs = limbs };
        }

        pub fn fromVarName(name: []const u8, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !Self {
            return Self.fromBaseAddr(try hint_utils.getRelocatableFromVarName(name, vm, ids_data, ap_tracking), vm);
        }

        pub fn fromValues(limbs: [NUM_LIMBS]Felt252) Self {
            return .{ .limbs = limbs };
        }

        pub fn insertFromVarName(
            self: *const Self,
            allocator: std.mem.Allocator,
            var_name: []const u8,
            vm: *CairoVM,
            ids_data: std.StringHashMap(HintReference),
            ap_tracking: ApTracking,
        ) !void {
            const addr = try hint_utils.getRelocatableFromVarName(var_name, vm, ids_data, ap_tracking);
            inline for (0..NUM_LIMBS) |i| {
                try vm.insertInMemory(allocator, try addr.addUint(i), MaybeRelocatable.fromFelt(self.limbs[i]));
            }
        }

        pub fn pack(self: *const Self, allocator: std.mem.Allocator) !Int {
            return packBigInt(allocator, NUM_LIMBS, self.limbs, 128);
        }

        pub fn pack86(self: *const Self, allocator: std.mem.Allocator) !Int {
            var result = try Int.initSet(allocator, 0);
            errdefer result.deinit();

            inline for (0..3) |i| {
                var tmp = try self.limbs[i].toSignedBigInt(allocator);
                defer tmp.deinit();

                try tmp.shiftLeft(&tmp, i * 86);

                try result.add(&result, &tmp);
            }

            return result;
        }


        pub fn split(allocator: std.mem.Allocator, num: Int) !Self {
            return Self.fromValues(try splitBigInt(allocator, num, NUM_LIMBS, 128));
        }

        // @TODO: implement from. It is dependent on split function.
        pub fn from(self: *Self, value: Int) !Self {
            // Assuming we have a `split` function in BigIntN.zig that performs the conversion.
            return self.split(value);
        }
    };
}

// Implements hint:
// %{
//    from starkware.cairo.common.cairo_secp.secp_utils import split
//    segments.write_arg(ids.res.address_, split(value))
// %}
///
pub fn nondetBigInt3(allocator: std.mem.Allocator, vm: *CairoVM, exec_scopes: *ExecutionScopes, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const res_reloc = try hint_utils.getRelocatableFromVarName("res", vm, ids_data, ap_tracking);
    const value = try exec_scopes.getValueRef(Int, "value");

    if (!value.isPositive()) return HintError.BigintToUsizeFail;

    var arg = try secp_utils.bigInt3Split(allocator, value);
    defer for (0..arg.len) |x| arg[x].deinit();

    const result: [3]MaybeRelocatable = .{
        MaybeRelocatable.fromInt(u512, try arg[0].to(u512)),
        MaybeRelocatable.fromInt(u512, try arg[1].to(u512)),
        MaybeRelocatable.fromInt(u512, try arg[2].to(u512)),
    };

    _ = try vm.segments.loadData(allocator, res_reloc, result[0..]);
}

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
pub fn hiMaxBitlen(vm: *CairoVM, allocator: std.mem.Allocator, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    var scalar_u = try BigInt3.fromVarName("scalar_u", vm, ids_data, ap_tracking);
    var scalar_v = try BigInt3.fromVarName("scalar_v", vm, ids_data, ap_tracking);

    // get number of bits in the highest limb
    const len_hi_u = scalar_u.limbs[2].numBits();
    const len_hi_v = scalar_v.limbs[2].numBits();

    const len_hi = @max(len_hi_u, len_hi_v);

    // equal to `len_hi.wrapping_sub(1)`
    const res = if (len_hi == 0) Felt252.Max.toInteger() else len_hi - 1;

    try hint_utils.insertValueFromVarName(allocator, "len_hi", MaybeRelocatable.fromInt(u256, res), vm, ids_data, ap_tracking);
}

// Tests

test "BigIntUtils: get bigint3 from base addr ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 0, 0 }, .{1} },
        .{ .{ 0, 1 }, .{2} },
        .{ .{ 0, 2 }, .{3} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    const x = try BigInt3.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm);

    try std.testing.expectEqual(Felt252.one(), x.limbs[0]);
    try std.testing.expectEqual(Felt252.two(), x.limbs[1]);
    try std.testing.expectEqual(Felt252.three(), x.limbs[2]);
}

test "BigIntUtils: get Bigint5 from base addr ok" {
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

    const x = try BigInt5.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm);

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

    try std.testing.expectError(MemoryError.UnknownMemoryCell, BigInt3.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm));
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

    try std.testing.expectError(MemoryError.UnknownMemoryCell, BigInt5.fromBaseAddr(Relocatable{ .segment_index = 0, .offset = 0 }, &vm));
}

test "BigIntUtils: get bigint3 from var name ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
    });

    vm.run_context.fp.* = 1;

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"x"});
    defer ids_data.deinit();

    const x = try BigInt3.fromVarName("x", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.one(), x.limbs[0]);
    try std.testing.expectEqual(Felt252.two(), x.limbs[1]);
    try std.testing.expectEqual(Felt252.three(), x.limbs[2]);
}

test "BigIntUtils: get bigint5 from var name ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{4} },
        .{ .{ 1, 4 }, .{5} },
    });

    vm.run_context.fp.* = 1;

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"x"});
    defer ids_data.deinit();

    const x = try BigInt5.fromVarName("x", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.one(), x.limbs[0]);
    try std.testing.expectEqual(Felt252.two(), x.limbs[1]);
    try std.testing.expectEqual(Felt252.three(), x.limbs[2]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 4), x.limbs[3]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 5), x.limbs[4]);
}

test "BigIntUtils: get bigint3 from var name with missing member fail" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp.* = 1;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"x"});
    defer ids_data.deinit();

    try std.testing.expectError(MemoryError.UnknownMemoryCell, BigInt3.fromVarName("x", &vm, ids_data, .{}));
}

test "BigIntUtils: get bigint5 from var name with missing member should fail" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{4} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp.* = 1;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"x"});
    defer ids_data.deinit();

    try std.testing.expectError(MemoryError.UnknownMemoryCell, BigInt5.fromVarName("x", &vm, ids_data, .{}));
}

test "BigIntUtils: get bigint3 from varname invalid reference should fail" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"x"});
    defer ids_data.deinit();

    try std.testing.expectError(HintError.UnknownIdentifier, BigInt3.fromVarName("x", &vm, ids_data, .{}));
}

test "BigIntUtils: get bigint5 from varname invalid reference should fail" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{4} },
        .{ .{ 1, 4 }, .{5} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"x"});
    defer ids_data.deinit();

    try std.testing.expectError(HintError.UnknownIdentifier, BigInt5.fromVarName("x", &vm, ids_data, .{}));
}

test "BigIntUtils: Run hiMaxBitlen ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "scalar_u", 0 },
            .{ "scalar_v", 3 },
            .{
                "len_hi",
                6,
            },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{1} },
        .{ .{ 1, 3 }, .{0} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{1} },
    });
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp.* = 0;
    vm.run_context.ap.* = 7;

    //Execute the hint
    const hint_code = "ids.len_hi = max(ids.scalar_u.d2.bit_length(), ids.scalar_v.d2.bit_length())-1";

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 6 }, .{0} },
    });
}

test "BigIntUtils: nondet bigint3 ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.segments.addSegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = try Int.initSet(std.testing.allocator, 7737125245533626718119526477371252455336267181195264773712524553362) });

    vm.run_context.pc.* = Relocatable.init(0, 0);
    vm.run_context.ap.* = 6;
    vm.run_context.fp.* = 6;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "res", 5 },
        },
    );
    defer ids_data.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(secp_utils.BASE_86, pow2ConstNz(86));

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, "from starkware.cairo.common.cairo_secp.secp_utils import split\n\nsegments.write_arg(ids.res.address_, split(value))", &constants, &exec_scopes);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{
            .{ 1, 11 }, .{773712524553362},
        },
        .{
            .{ 1, 12 }, .{57408430697461422066401280},
        },
        .{
            .{ 1, 13 }, .{1292469707114105},
        },
    });
}

test "BigIntUtils: nondet bigint3 split error" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.segments.addSegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = try Int.initSet(std.testing.allocator, -1) });

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "res", 5 },
        },
    );
    defer ids_data.deinit();

    try std.testing.expectError(HintError.BigintToUsizeFail, testing_utils.runHint(std.testing.allocator, &vm, ids_data, "from starkware.cairo.common.cairo_secp.secp_utils import split\n\nsegments.write_arg(ids.res.address_, split(value))", undefined, &exec_scopes));
}

test "BigIntUtils: nondet bigint3 value not in scope" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.segments.addSegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    vm.run_context.pc.* = Relocatable.init(0, 0);
    vm.run_context.ap.* = 6;
    vm.run_context.fp.* = 6;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "res", 5 },
        },
    );
    defer ids_data.deinit();

    try std.testing.expectError(HintError.VariableNotInScopeError, testing_utils.runHint(std.testing.allocator, &vm, ids_data, "from starkware.cairo.common.cairo_secp.secp_utils import split\n\nsegments.write_arg(ids.res.address_, split(value))", undefined, &exec_scopes));
}

test "BigIntUtils: u384 pack86" {
    var val = try Uint384.fromValues(.{
        Felt252.fromInt(u8, 10),
        Felt252.fromInt(u8, 10),
        Felt252.fromInt(u8, 10),
    }).pack86(std.testing.allocator);
    defer val.deinit();

    try std.testing.expectEqual(
        59863107065073783529622931521771477038469668772249610,
        val.to(u384),
    );

    var val1 = try Uint384.fromValues(.{
        Felt252.fromInt(u128, 773712524553362),
        Felt252.fromInt(u128, 57408430697461422066401280),
        Felt252.fromInt(u128, 1292469707114105),
    }).pack86(std.testing.allocator);
    defer val1.deinit();

    try std.testing.expectEqual(
        7737125245533626718119526477371252455336267181195264773712524553362,
        try val1.to(u384),
    );
}
