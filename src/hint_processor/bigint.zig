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
pub fn bigintPackDivModHint(vm: *CairoVM, exec_scopes: *ExecutionScopes, idsData: std.StringHashMap(HintReference), apTracking: ApTracking) !void {
    var p: BigInt3 = try BigInt3.fromVarName("P", vm, idsData, apTracking).pack86();

    var x: BigIntN = try {
        var x_bigint5 = try BigInt5.fromVarName("x", vm, idsData, apTracking);
        var x_lower = BigInt3{
            .limbs = x_bigint5.limbs[0..3],
        };
        x_lower = try x_lower.pack86();
        const d3 = x_bigint5.limbs[3];
        const d4 = x_bigint5.limbs[4];
        x_lower + d3 * BigIntN.from(BASE.pow(3)) + d4 * BigIntN.from(BASE.pow(4));
    };

    var y: BigIntN = try BigInt3.fromVarName("y", vm, idsData, apTracking).pack86();

    const res = try divMod(&x, &y, &p);
    try exec_scopes.assignOrUpdateVariable("res", res);
    try exec_scopes.assignOrUpdateVariable("value", res);
    try exec_scopes.assignOrUpdateVariable("x", x);
    try exec_scopes.assignOrUpdateVariable("y", y);
    try exec_scopes.assignOrUpdateVariable("p", p);
}

/// Implements hint:
/// ```python
/// k = safe_div(res * y - x, p)
/// value = k if k > 0 else 0 - k
/// ids.flag = 1 if k > 0 else 0
/// ```
pub fn bigIntSafeDivHint(allocator: std.mem.Allocator, vm: *CairoVM, exec_scopes: *ExecutionScopes, idsData: *std.HashMap(std.hash_map.DefaultHashFn, []const u8, HintReference, std.hash_map.DefaultMaxLoad), apTracking: *ApTracking) !void {
    const res = exec_scopes.get("res");
    const x = exec_scopes.get("x");
    const y = exec_scopes.get("y");
    const p = exec_scopes.get("p");

    const k = safeDivBigInt(res * y - x, p);

    const result = if (k >= 0) {
        .{ k, Felt252.one() };
    } else {
        .{ -k, Felt252.zero() };
    };

    try exec_scopes.assignOrUpdateVariable("k", k);
    try exec_scopes.assignOrUpdateVariable("value", result[0]);

    insertValueFromVarName(allocator, "flag", result[1], vm, idsData, apTracking);
}

// Input:
// x = UnreducedBigInt5(0x38a23ca66202c8c2a72277, 0x6730e765376ff17ea8385, 0xca1ad489ab60ea581e6c1, 0, 0);
// y = UnreducedBigInt3(0x20a4b46d3c5e24cda81f22, 0x967bf895824330d4273d0, 0x541e10c21560da25ada4c);
// p = BigInt3(0x8a03bbfd25e8cd0364141, 0x3ffffffffffaeabb739abd, 0xfffffffffffffffffffff);
// expected: value = res = 109567829260688255124154626727441144629993228404337546799996747905569082729709 (py int)
test "big int pack div mod hint" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    var ids_data = testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "x", 0 },
        .{ "y", 5 },
        .{ "P", 8 },
    });

    defer ids_data.deinit();

    vm.run_context.fp.* = Relocatable{
        .offset = 0,
        .segment_index = 0,
    };

    // Set up memory segments in the virtual machine.
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0x38a23ca66202c8c2a72277} },
        .{ .{ 1, 1 }, .{0x38a23ca66202c8c2a72277} },
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

    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.BIGINT_PACK_DIV_MOD_HINT, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const res_loc = try hint_utils.getRelocatableFromVarName("res", &vm, ids_data, .{});
    const res_value = try hint_utils.getBigIntFromRelocatable(&vm, res_loc);

    const value_loc = try hint_utils.getRelocatableFromVarName("value", &vm, ids_data, .{});
    const value = try hint_utils.getBigIntFromRelocatable(&vm, value_loc);

    const y_loc = try hint_utils.getRelocatableFromVarName("y", &vm, ids_data, .{});
    const y = try hint_utils.getBigIntFromRelocatable(&vm, y_loc);

    const x_loc = try hint_utils.getRelocatableFromVarName("x", &vm, ids_data, .{});
    const x = try hint_utils.getBigIntFromRelocatable(&vm, x_loc);

    const p_loc = try hint_utils.getRelocatableFromVarName("p", &vm, ids_data, .{});
    const p = try hint_utils.getBigIntFromRelocatable(&vm, p_loc);

    try std.testing.expectEqual(109567829260688255124154626727441144629993228404337546799996747905569082729709, res_value);
    try std.testing.expectEqual(109567829260688255124154626727441144629993228404337546799996747905569082729709, value);
    try std.testing.expectEqual(38047400353360331012910998489219098987968251547384484838080352663220422975266, y);
    try std.testing.expectEqual(91414600319290532004473480113251693728834511388719905794310982800988866814583, x);
    try std.testing.expectEqual(115792089237316195423570985008687907852837564279074904382605163141518161494337, p);
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

    var ids_data = testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "res", 109567829260688255124154626727441144629993228404337546799996747905569082729709 },
        .{ "x", 91414600319290532004473480113251693728834511388719905794310982800988866814583 },
        .{ "y", 38047400353360331012910998489219098987968251547384484838080352663220422975266 },
        .{ "P", 115792089237316195423570985008687907852837564279074904382605163141518161494337 },
        .{ "flag", 0 },
    });

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
