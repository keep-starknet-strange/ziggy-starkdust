const hint_utils = @import("hint_utils.zig");
const std = @import("std");
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const testing_utils = @import("testing_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const hint_codes = @import("builtin_hint_codes.zig");
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintData = @import("hint_processor_def.zig").HintData;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const BigInt3 = @import("builtin_hint_processor/secp/bigint_utils.zig").BigInt3;
const BigInt5 = @import("builtin_hint_processor/secp/bigint_utils.zig").BigInt5;
const BigIntN = @import("builtin_hint_processor/secp/bigint_utils.zig").BigIntN;
const Int = @import("std").math.big.int.Managed;
const BASE = @import("../math/fields/constants.zig").BASE;
const divMod = @import("../math/fields/helper.zig").divMod;
const safeDivBigInt = @import("../math/fields/helper.zig").safeDivBigInt;
const insertValueFromVarName = @import("../hint_processor/hint_utils.zig").insertValueFromVarName;

/// Implements hint:
/// ```python
/// from starkware.cairo.common.cairo_secp.secp_utils import pack
/// from starkware.cairo.common.math_utils import as_int
/// from starkware.python.math_utils import div_mod, safe_div
///
/// p = pack(ids.P, PRIME)
/// x = pack(ids.x, PRIME) + as_int(ids.x.d3, PRIME) * ids.BASE ** 3 + as_int(ids.x.d4, PRIME) * ids.BASE ** 4
/// y = pack(ids.y, PRIME)
///
/// value = res = div_mod(x, y, p)
/// ```
pub fn bigintPackDivModHint(vm: *CairoVM, allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes, idsData: std.StringHashMap(HintReference), apTracking: ApTracking) !void {
    // Initiate BigInt default element
    var p: BigInt3 = .{};
    p = try p.fromVarName("P", vm, idsData, apTracking);
    var p_packed = try p.pack(allocator);

    std.debug.print("p_packed: {}\n", .{p_packed});

    const p_packed_i256 = try p_packed.to(i256);
    std.debug.print("p_packed_i256: {}\n", .{p_packed_i256});

    var x: BigInt5 = .{};

    const x_bigint5 = try x.fromVarName("x", vm, idsData, apTracking);
    var x_lower: BigInt3 = .{};

    // take first three limbs of x_bigint5 and pack them into x_lower
    for (x_bigint5.limbs, 0..) |limb, i| {
        if (i < 3) {
            x_lower.limbs[i] = limb;
        }
    }

    const x_lower_packed = try x_lower.pack(allocator);
    std.debug.print("x_lower_packed: {}\n", .{x_lower_packed});
    const d3 = x_bigint5.limbs[3].toInteger();
    const d4 = x_bigint5.limbs[4].toInteger();
    const x_lower_packed_256 = try x_lower_packed.to(i256);
    std.debug.print("xxx: {}\n", .{x_lower_packed_256});
    const c = x_lower_packed_256 + @as(i512, @intCast(d3)) * @as(i512, @intCast(std.math.pow(u512, BASE, 3))) + @as(i512, @intCast(d4)) * @as(i512, @intCast(std.math.pow(u512, BASE, 4)));
    std.debug.print("c: {}\n", .{c});
    const x_packed = c;

    var y: BigInt3 = .{};

    y = try y.fromVarName("y", vm, idsData, apTracking);

    var y_packed = try y.pack(allocator);

    const y_packed_i256 = try y_packed.to(i256);
    const res = try divMod(x_packed, y_packed_i256, p_packed_i256);

    try exec_scopes.assignOrUpdateVariable("res", .{
        .i512 = res,
    });
    try exec_scopes.assignOrUpdateVariable("value", .{
        .i512 = res,
    });
    try exec_scopes.assignOrUpdateVariable("x", .{
        .i512 = x_packed,
    });
    try exec_scopes.assignOrUpdateVariable("y", .{
        .i512 = y_packed_i256,
    });
    try exec_scopes.assignOrUpdateVariable("p", .{
        .i512 = p_packed_i256,
    });
}

/// Implements hint:
/// ```python
/// k = safe_div(res * y - x, p)
/// value = k if k > 0 else 0 - k
/// ids.flag = 1 if k > 0 else 0
/// ```
pub fn bigIntSafeDivHint(allocator: std.mem.Allocator, vm: *CairoVM, exec_scopes: *ExecutionScopes, ids_data: std.StringHashMap(HintReference), apTracking: ApTracking) !void {
    const res = (try exec_scopes.getFelt("res")).toInteger();
    const x = (try exec_scopes.getFelt("x")).toInteger();
    const y = (try exec_scopes.getFelt("y")).toInteger();
    const p = (try exec_scopes.getFelt("p")).toInteger();

    const k = try safeDivBigInt(@as(i256, @intCast(res * y - x)), @as(i256, @intCast(p)));

    var result: struct { value: i256, flag: Felt252 } = undefined;

    if (k >= 0) {
        result = .{ .value = k, .flag = Felt252.one() };
    } else {
        result = .{ .value = -k, .flag = Felt252.zero() };
    }

    const resultValue = result.value;
    const flag = result.flag;

    try exec_scopes.assignOrUpdateVariable("k", k);
    try exec_scopes.assignOrUpdateVariable("value", resultValue);

    insertValueFromVarName(allocator, "flag", flag, vm, ids_data, apTracking);
}

// Input:
// x = UnreducedBigInt5(0x38a23ca66202c8c2a72277, 0x6730e765376ff17ea8385, 0xca1ad489ab60ea581e6c1, 0, 0);
// y = UnreducedBigInt3(0x20a4b46d3c5e24cda81f22, 0x967bf895824330d4273d0, 0x541e10c21560da25ada4c);
// p = BigInt3(0x8a03bbfd25e8cd0364141, 0x3ffffffffffaeabb739abd, 0xfffffffffffffffffffff);
// expected: value = res = 109567829260688255124154626727441144629993228404337546799996747905569082729709 (py int)
test "big int pack div mod hint" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "x", 0 },
            .{ "y", 5 },
            .{ "P", 8 },
        },
    );

    defer ids_data.deinit();

    // Set up memory segments in the virtual machine.
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0x38a23ca66202c8c2a72277} },
        .{ .{ 1, 1 }, .{0x6730e765376ff17ea8385} },
        .{ .{ 1, 2 }, .{0xca1ad489ab60ea581e6c1} },
        .{ .{ 1, 3 }, .{0} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0x20a4b46d3c5e24cda81f22} },
        .{ .{ 1, 6 }, .{0x967bf895824330d4273d0} },
        .{ .{ 1, 7 }, .{0x541e10c21560da25ada4c} },
        .{ .{ 1, 8 }, .{0x8a03bbfd25e8cd0364141} },
        .{ .{ 1, 9 }, .{0x3ffffffffffaeabb739abd} },
        .{ .{ 1, 10 }, .{0xfffffffffffffffffffff} },
    });

    vm.run_context.fp.* = Relocatable.init(1, 0);

    defer vm.segments.memory.deinitData(std.testing.allocator);

    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.BIGINT_PACK_DIV_MOD_HINT, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const res_loc = try hint_utils.getRelocatableFromVarName("res", &vm, ids_data, .{});
    const res_value = try vm.getFelt(res_loc);

    std.debug.print("res: {}\n", .{res_value});

    const value_loc = try hint_utils.getRelocatableFromVarName("value", &vm, ids_data, .{});
    const value = try vm.getFelt(value_loc);

    const y_loc = try hint_utils.getRelocatableFromVarName("y", &vm, ids_data, .{});
    const y = try vm.getFelt(y_loc);

    const x_loc = try hint_utils.getRelocatableFromVarName("x", &vm, ids_data, .{});
    const x = try vm.getFelt(x_loc);

    const p_loc = try hint_utils.getRelocatableFromVarName("P", &vm, ids_data, .{});
    const p = try vm.getFelt(p_loc);

    try std.testing.expectEqual(109567829260688255124154626727441144629993228404337546799996747905569082729709, res_value.toInteger());
    try std.testing.expectEqual(109567829260688255124154626727441144629993228404337546799996747905569082729709, value.toInteger());
    try std.testing.expectEqual(38047400353360331012910998489219098987968251547384484838080352663220422975266, y.toInteger());
    try std.testing.expectEqual(91414600319290532004473480113251693728834511388719905794310982800988866814583, x.toInteger());
    try std.testing.expectEqual(115792089237316195423570985008687907852837564279074904382605163141518161494337, p.toInteger());
}

// Input:
// res = 109567829260688255124154626727441144629993228404337546799996747905569082729709
// y = 38047400353360331012910998489219098987968251547384484838080352663220422975266
// x = 91414600319290532004473480113251693728834511388719905794310982800988866814583
// p = 115792089237316195423570985008687907852837564279074904382605163141518161494337
// Output:
// k = 36002209591245282109880156842267569109802494162594623391338581162816748840003
// value = 36002209591245282109880156842267569109802494162594623391338581162816748840003
// ids.flag = 1
test "big int safe div hint" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    var ids_data = testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "res", 109567829260688255124154626727441144629993228404337546799996747905569082729709 },
            .{ "x", 91414600319290532004473480113251693728834511388719905794310982800988866814583 },
            .{ "y", 38047400353360331012910998489219098987968251547384484838080352663220422975266 },
            .{ "P", 115792089237316195423570985008687907852837564279074904382605163141518161494337 },
            .{ "flag", 0 },
        },
    );

    defer ids_data.deinit();

    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.BIGINT_SAFE_DIV, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const k_loc = try hint_utils.getRelocatableFromVarName("k", &vm, ids_data, .{});
    const k = try hint_utils.getBigIntFromRelocatable(&vm, k_loc);

    const value_loc = try hint_utils.getRelocatableFromVarName("value", &vm, ids_data, .{});
    const value = try hint_utils.getBigIntFromRelocatable(&vm, value_loc);

    try std.testing.expectEqual(36002209591245282109880156842267569109802494162594623391338581162816748840003, k);
    try std.testing.expectEqual(36002209591245282109880156842267569109802494162594623391338581162816748840003, value);
}
