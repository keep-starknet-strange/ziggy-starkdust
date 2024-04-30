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
const field_helper = @import("../math/fields/helper.zig");
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
pub fn bigintPackDivModHint(allocator: std.mem.Allocator, vm: *CairoVM, exec_scopes: *ExecutionScopes, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    // Initiate BigInt default element
    var p = try (try BigInt3.fromVarName("P", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer p.deinit();

    var x: Int = blk: {
        const x_bigint5 = try BigInt5.fromVarName("x", vm, ids_data, ap_tracking);

        var x_lower = try BigInt3.fromValues([3]Felt252{
            x_bigint5.limbs[0], x_bigint5.limbs[1], x_bigint5.limbs[2],
        }).pack86(allocator);
        defer x_lower.deinit();

        var d3 = try x_bigint5.limbs[3].toSignedBigInt(allocator);
        defer d3.deinit();

        var d4 = try x_bigint5.limbs[3].toSignedBigInt(allocator);
        defer d4.deinit();

        var tmp = try Int.init(allocator);
        defer tmp.deinit();

        var base = try Int.initSet(allocator, BASE);
        defer base.deinit();

        var result = try Int.init(allocator);
        errdefer result.deinit();

        try tmp.pow(&base, 3);

        try tmp.mul(&d3, &tmp);

        try result.add(&x_lower, &tmp);

        try tmp.pow(&base, 4);

        try tmp.mul(&d4, &tmp);

        try result.add(&result, &tmp);

        break :blk result;
    };
    errdefer x.deinit();

    var y = try (try BigInt3.fromVarName("y", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer y.deinit();

    var res = try field_helper.divModBigInt(allocator, &x, &y, &p);
    errdefer res.deinit();

    try exec_scopes.assignOrUpdateVariable("res", .{
        .big_int = res,
    });

    try exec_scopes.assignOrUpdateVariable("value", .{
        .big_int = try res.clone(),
    });

    try exec_scopes.assignOrUpdateVariable("x", .{
        .big_int = x,
    });

    try exec_scopes.assignOrUpdateVariable("y", .{
        .big_int = y,
    });

    try exec_scopes.assignOrUpdateVariable("p", .{
        .big_int = p,
    });
}

/// Implements hint:
/// ```python
/// k = safe_div(res * y - x, p)
/// value = k if k > 0 else 0 - k
/// ids.flag = 1 if k > 0 else 0
/// ```
pub fn bigIntSafeDivHint(allocator: std.mem.Allocator, vm: *CairoVM, exec_scopes: *ExecutionScopes, ids_data: std.StringHashMap(HintReference), apTracking: ApTracking) !void {
    const res = try exec_scopes.getValueRef(Int, "res");
    const x = try exec_scopes.getValueRef(Int, "x");
    const y = try exec_scopes.getValueRef(Int, "y");
    const p = try exec_scopes.getValueRef(Int, "p");

    var tmp = try Int.init(allocator);
    errdefer tmp.deinit();

    var tmp2 = try Int.init(allocator);
    errdefer tmp2.deinit();

    try tmp.mul(res, y);
    try tmp.sub(&tmp, x);
    try tmp.divFloor(&tmp2, &tmp, p);

    var flag: Felt252 = undefined;

    try tmp2.copy(tmp.toConst());
    if (tmp.isPositive() or tmp.eqlZero()) {
        flag = Felt252.one();
    } else {
        flag = Felt252.zero();
        tmp2.negate();
    }

    // k == tmp
    // result == tmp2

    try exec_scopes.assignOrUpdateVariable("k", .{ .big_int = tmp });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = tmp2 });
    try insertValueFromVarName(allocator, "flag", MaybeRelocatable.fromFelt(flag), vm, ids_data, apTracking);
}

test "big int pack div mod hint" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "x", 0 },
            .{ "y", 5 },
            .{ "P", 8 },
        },
    );

    defer ids_data.deinit();

    vm.run_context.fp = 0;
    inline for (0..11) |_| _ = try vm.addMemorySegment();

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

    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.BIGINT_PACK_DIV_MOD, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqual(109567829260688255124154626727441144629993228404337546799996747905569082729709, try ((try exec_scopes.getValue(Int, "res"))).to(u512));
    try std.testing.expectEqual(109567829260688255124154626727441144629993228404337546799996747905569082729709, try ((try exec_scopes.getValue(Int, "res"))).to(u512));
    try std.testing.expectEqual(38047400353360331012910998489219098987968251547384484838080352663220422975266, try ((try exec_scopes.getValue(Int, "y"))).to(u512));
    try std.testing.expectEqual(91414600319290532004473480113251693728834511388719905794310982800988866814583, try ((try exec_scopes.getValue(Int, "x"))).to(u512));
    try std.testing.expectEqual(115792089237316195423570985008687907852837564279074904382605163141518161494337, try ((try exec_scopes.getValue(Int, "p"))).to(u512));
}

test "big int safe div hint" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "flag", 0 },
        },
    );

    defer ids_data.deinit();

    // Set the frame pointer to point to the beginning of the stack.
    vm.run_context.fp = 0;
    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("res", .{ .big_int = try Int.initSet(std.testing.allocator, 109567829260688255124154626727441144629993228404337546799996747905569082729709) });
    try exec_scopes.assignOrUpdateVariable("y", .{ .big_int = try Int.initSet(std.testing.allocator, 38047400353360331012910998489219098987968251547384484838080352663220422975266) });
    try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = try Int.initSet(std.testing.allocator, 91414600319290532004473480113251693728834511388719905794310982800988866814583) });
    try exec_scopes.assignOrUpdateVariable("p", .{ .big_int = try Int.initSet(std.testing.allocator, 115792089237316195423570985008687907852837564279074904382605163141518161494337) });

    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.BIGINT_SAFE_DIV, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqual(36002209591245282109880156842267569109802494162594623391338581162816748840003, try ((try exec_scopes.getValue(Int, "k")).to(u512)));

    try std.testing.expectEqual(36002209591245282109880156842267569109802494162594623391338581162816748840003, try ((try exec_scopes.getValue(Int, "value")).to(u512)));
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{1} }});
}
