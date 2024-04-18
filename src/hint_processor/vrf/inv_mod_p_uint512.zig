const std = @import("std");
const CairoVM = @import("../../vm/core.zig").CairoVM;
const hint_utils = @import("../hint_utils.zig");
const HintReference = @import("../hint_processor_def.zig").HintReference;
const HintProcessor = @import("../hint_processor_def.zig").CairoVMHintProcessor;
const testing_utils = @import("../testing_utils.zig");
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const hint_codes = @import("../builtin_hint_codes.zig");
const Relocatable = @import("../../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../vm/memory/relocatable.zig").MaybeRelocatable;
const ApTracking = @import("../../vm/types/programjson.zig").ApTracking;
const HintData = @import("../hint_processor_def.zig").HintData;
const ExecutionScopes = @import("../../vm/types/execution_scopes.zig").ExecutionScopes;
const HintType = @import("../../vm/types/execution_scopes.zig").HintType;

const helper = @import("../../math/fields/helper.zig");
const MathError = @import("../../vm/error.zig").MathError;
const HintError = @import("../../vm/error.zig").HintError;
const CairoVMError = @import("../../../vm/error.zig").CairoVMError;

const bigint_utils = @import("../builtin_hint_processor/secp/bigint_utils.zig");

const Uint256 = @import("../uint256_utils.zig").Uint256;
const Uint512 = bigint_utils.Uint512;
const Int = @import("std").math.big.int.Managed;

const fromBigInt = @import("../../math/fields/starknet.zig").fromBigInt;
const STARKNET_PRIME = @import("../../math/fields/starknet.zig").STARKNET_PRIME;

// Implements hint:
// %{
//     def pack_512(u, num_bits_shift: int) -> int:
//         limbs = (u.d0, u.d1, u.d2, u.d3)
//         return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//     x = pack_512(ids.x, num_bits_shift = 128)
//     p = ids.p.low + (ids.p.high << 128)
//     x_inverse_mod_p = pow(x,-1, p)

//     x_inverse_mod_p_split = (x_inverse_mod_p & ((1 << 128) - 1), x_inverse_mod_p >> 128)

//     ids.x_inverse_mod_p.low = x_inverse_mod_p_split[0]
//     ids.x_inverse_mod_p.high = x_inverse_mod_p_split[1]
// %}
pub fn invModPUint512(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var x = try (try Uint512.fromVarName("x", vm, ids_data, ap_tracking)).pack(allocator);
    defer x.deinit();

    var p = try (try Uint256.fromVarName("p", vm, ids_data, ap_tracking)).pack(allocator);
    defer p.deinit();

    var one = try Int.initSet(allocator, 1);
    defer one.deinit();

    var x_inverse_mod_p = try helper.divModBigInt(allocator, &one, &x, &p);
    defer x_inverse_mod_p.deinit();

    var x_inverse_mod_p_felt = try fromBigInt(allocator, x_inverse_mod_p);
    if (!x_inverse_mod_p.isPositive())
        x_inverse_mod_p_felt = x_inverse_mod_p_felt.neg();

    try Uint256.fromFelt(x_inverse_mod_p_felt).insertFromVarName(allocator, "x_inverse_mod_p", vm, ids_data, ap_tracking);
}

test "Uint512: pack 512" {
    var valu512 = try Uint512.fromValues(.{
        Felt252.fromInt(u64, 13123),
        Felt252.fromInt(u64, 534354),
        Felt252.fromInt(u64, 9901823),
        Felt252.fromInt(u64, 7812371),
    }).pack(std.testing.allocator);
    defer valu512.deinit();

    var val = try Int.initSet(std.testing.allocator, 307823090550532533958111616786199064327151160536573522012843486812312234767517005952120863393832102810613083123402814796611);
    defer val.deinit();

    try std.testing.expect(valu512.eql(val));

    var valu512_2 = try Uint512.fromValues(.{
        Felt252.fromInt(u64, 90812398),
        Felt252.fromInt(u64, 55),
        Felt252.fromInt(u64, 83127),
        Felt252.fromInt(u64, 45312309123),
    }).pack(std.testing.allocator);
    defer valu512_2.deinit();

    var val_2 = try Int.initSet(std.testing.allocator, 1785395884837388090117385402351420305430103423113021825538726783888669416377532493875431795584456624829488631993250169127284718);
    defer val_2.deinit();

    try std.testing.expect(valu512_2.eql(val_2));
}

test "Uint512: invModPUint512 ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.segments.addSegment();

    vm.run_context.fp.* = 25;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "x", -5 }, .{ "p", -10 }, .{ "x_inverse_mod_p", -20 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 20 }, .{101} }, //ids.x.d0
        .{ .{ 1, 21 }, .{2} }, // ids.x.d1
        .{ .{ 1, 22 }, .{15} }, // ids.x.d2
        .{ .{ 1, 23 }, .{61} }, // ids.x.d3
        .{ .{ 1, 15 }, .{201385395114098847380338600778089168199} }, // ids.p.low
        .{ .{ 1, 16 }, .{64323764613183177041862057485226039389} }, // ids.p.high
    });

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.INV_MOD_P_UINT512,
        undefined,
        &exec_scopes,
    );

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 5 }, .{80275402838848031859800366538378848249} },
        .{ .{ 1, 6 }, .{5810892639608724280512701676461676039} },
    });
}
