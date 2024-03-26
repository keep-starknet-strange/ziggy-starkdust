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
    const p_packed = try p.pack(allocator);

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

    const d3 = x_bigint5.limbs[3].toInteger();
    const d4 = x_bigint5.limbs[4].toInteger();

    const x_lower_packed_i512 = try x_lower_packed.to(i512);

    const x_packed_i512 = x_lower_packed_i512 + @as(i512, @intCast(d3)) * @as(i512, @intCast(std.math.pow(u512, BASE, 3))) + @as(i512, @intCast(d4)) * @as(i512, @intCast(std.math.pow(u512, BASE, 4)));

    var y: BigInt3 = .{};

    y = try y.fromVarName("y", vm, idsData, apTracking);

    var y_packed = try y.pack(allocator);

    const y_packed_512 = try y_packed.to(i512);

    const p_packed_512 = try p_packed.to(i512);

    const num = @divFloor(x_packed_i512, y_packed_512);

    const res = @mod(num, p_packed_512);

    const res_256 = @as(i256, @intCast(res));

    try exec_scopes.assignOrUpdateVariable("res", .{
        .i256 = res_256,
    });

    try exec_scopes.assignOrUpdateVariable("value", .{
        .i256 = res_256,
    });
    try exec_scopes.assignOrUpdateVariable("x", .{
        .i512 = x_packed_i512,
    });
    try exec_scopes.assignOrUpdateVariable("y", .{
        .i512 = y_packed_512,
    });
    try exec_scopes.assignOrUpdateVariable("P", .{
        .i512 = p_packed_512,
    });
}

/// Implements hint:
/// ```python
/// k = safe_div(res * y - x, p)
/// value = k if k > 0 else 0 - k
/// ids.flag = 1 if k > 0 else 0
/// ```
pub fn bigIntSafeDivHint(allocator: std.mem.Allocator, vm: *CairoVM, exec_scopes: *ExecutionScopes, ids_data: std.StringHashMap(HintReference), apTracking: ApTracking) !void {
    const res = (try exec_scopes.get("res")).i256;
    const x = (try exec_scopes.get("x")).i256;
    const y = (try exec_scopes.get("y")).i256;
    const p = (try exec_scopes.get("p")).i256;

    const k = try safeDivBigInt(@as(i256, @intCast(res * y - x)), @as(i256, @intCast(p)));

    var result: struct { value: i256, flag: Felt252 } = undefined;

    if (k >= 0) {
        result = .{ .value = k, .flag = Felt252.one() };
    } else {
        result = .{ .value = -k, .flag = Felt252.zero() };
    }

    const resultValue = result.value;
    const flag = MaybeRelocatable.fromFelt(result.flag);

    try exec_scopes.assignOrUpdateVariable("k", .{ .i256 = k });
    try exec_scopes.assignOrUpdateVariable("value", .{ .i256 = resultValue });
    try insertValueFromVarName(allocator, "flag", flag, vm, ids_data, apTracking);
}

test "big int pack div mod hint" {
    var vm = try CairoVM.init(std.testing.allocator, .{});

    defer vm.deinit();

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "x", 0 },
            .{ "y", 5 },
            .{ "P", 8 },
            .{ "res", 11 },
            .{ "value", 12 },
        },
    );

    defer ids_data.deinit();

    // Set up memory segments in the virtual machine.
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{100} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{0} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{20} },
        .{ .{ 1, 6 }, .{0} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{7} },
        .{ .{ 1, 9 }, .{0} },
        .{ .{ 1, 10 }, .{0} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 0;

    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.BIGINT_PACK_DIV_MOD_HINT, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("res", .{ .i256 = 0 });

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    const res_value = (try exec_scopes.get("res")).i256;
    const value = (try exec_scopes.get("value")).i256;

    const y_loc = try hint_utils.getRelocatableFromVarName("y", &vm, ids_data, .{});
    const y = try vm.getFelt(y_loc);

    const x_loc = try hint_utils.getRelocatableFromVarName("x", &vm, ids_data, .{});
    const x = try vm.getFelt(x_loc);

    const p_loc = try hint_utils.getRelocatableFromVarName("P", &vm, ids_data, .{});
    const p = try vm.getFelt(p_loc);

    try std.testing.expectEqual(5, res_value);
    try std.testing.expectEqual(5, value);
    try std.testing.expectEqual(20, y.toInteger());
    try std.testing.expectEqual(100, x.toInteger());
    try std.testing.expectEqual(7, p.toInteger());
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
    vm.run_context.*.fp.* = 0;
    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    try exec_scopes.assignOrUpdateVariable("res", .{ .i256 = 10 });
    try exec_scopes.assignOrUpdateVariable("y", .{ .i256 = 2 });
    try exec_scopes.assignOrUpdateVariable("x", .{ .i256 = 5 });
    try exec_scopes.assignOrUpdateVariable("p", .{ .i256 = 3 });

    defer exec_scopes.deinit();

    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.BIGINT_SAFE_DIV, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    const k = (try exec_scopes.get("k")).i256;
    const value = (try exec_scopes.get("value")).i256;

    const flag_loc = try hint_utils.getRelocatableFromVarName("flag", &vm, ids_data, .{});
    const flag = try vm.getFelt(flag_loc);

    try std.testing.expectEqual(5, k);
    try std.testing.expectEqual(5, value);
    try std.testing.expectEqual(1, flag.toInteger());
}
