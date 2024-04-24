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
const secp_utils = @import("../builtin_hint_processor/secp/secp_utils.zig");

const Uint256 = @import("../uint256_utils.zig").Uint256;
const Uint512 = bigint_utils.Uint512;
const BigInt3 = bigint_utils.BigInt3;
const Int = @import("std").math.big.int.Managed;

const fromBigInt = @import("../../math/fields/starknet.zig").fromBigInt;
const STARKNET_PRIME = @import("../../math/fields/starknet.zig").STARKNET_PRIME;

/// Implements hint:
/// ```python
/// from starkware.cairo.common.cairo_secp.secp_utils import pack
/// SECP_P=2**255-19
///
/// x = pack(ids.x, PRIME) % SECP_P
/// ```
pub fn ed25519IsZeroPack(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var x = try (try BigInt3.fromVarName("x", vm, ids_data, ap_tracking)).pack86(allocator);
    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var tmp2 = try Int.initSet(allocator, secp_utils.SECP_P_V2);
    errdefer tmp2.deinit();

    {
        errdefer x.deinit();
        try tmp.divFloor(&x, &x, &tmp2);

        try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = x });
    }

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = tmp2 });
}

/// Implements hint:
/// ```python
/// from starkware.cairo.common.cairo_secp.secp_utils import pack
/// SECP_P=2**255-19
///
/// value = pack(ids.x, PRIME) % SECP_P
/// ```
pub fn ed25519Reduce(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var secp_p = try Int.initSet(allocator, secp_utils.SECP_P_V2);
    errdefer secp_p.deinit();

    var x = try (try BigInt3.fromVarName("x", vm, ids_data, ap_tracking)).pack86(allocator);

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    {
        errdefer x.deinit();

        try tmp.divFloor(&x, &x, &secp_p);
        try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = x });
    }

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
}

/// Implements hint:
/// ```python
/// SECP_P=2**255-19
/// from starkware.python.math_utils import div_mod
///
/// value = x_inv = div_mod(1, x, SECP_P)
/// ```
pub fn ed25519IsZeroAssignScopeVars(
    allocator: std.mem.Allocator,
    exec_scopes: *ExecutionScopes,
) !void {
    const x = try exec_scopes.getValue(Int, "x");

    var secp_p = try Int.initSet(allocator, secp_utils.SECP_P_V2);
    errdefer secp_p.deinit();

    var tmp = try Int.initSet(allocator, 1);
    defer tmp.deinit();

    var x_inv = try helper.divModBigInt(allocator, &tmp, &x, &secp_p);
    {
        errdefer x_inv.deinit();

        try exec_scopes.assignOrUpdateVariable("x_inv", .{ .big_int = try x_inv.clone() });
        try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = x_inv });
    }

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
}

const SECP_P_D0: i128 = 77371252455336267181195245;
const SECP_P_D1: i128 = 77371252455336267181195263;
const SECP_P_D2: i128 = 9671406556917033397649407;

fn assertIsZeroPackEd25519Equals(comptime x_d0: i128, comptime x_d1: i128, comptime x_d2: i128, expected: Int) !void {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "x", 0 },
    });
    defer ids_data.deinit();

    vm.run_context.fp.* = 0;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{x_d0} },
        .{ .{ 1, 1 }, .{x_d1} },
        .{ .{ 1, 2 }, .{x_d2} },
    });

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.IS_ZERO_PACK_ED25519,
        undefined,
        &exec_scopes,
    );

    const x = try exec_scopes.getValue(Int, "x");
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    try std.testing.expect(expected.eql(x));
    var exp_secp_p = try Int.initSet(std.testing.allocator, secp_utils.SECP_P_V2);
    defer exp_secp_p.deinit();

    try std.testing.expect(exp_secp_p.eql(secp_p));
}

fn assertReduceEd25519Equals(x_d0: i128, x_d1: i128, x_d2: i128, expected: Int) !void {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "x", 0 },
    });
    defer ids_data.deinit();

    vm.run_context.fp.* = 0;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{x_d0} },
        .{ .{ 1, 1 }, .{x_d1} },
        .{ .{ 1, 2 }, .{x_d2} },
    });

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.REDUCE_ED25519,
        undefined,
        &exec_scopes,
    );

    const x = try exec_scopes.getValue(Int, "value");
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    try std.testing.expect(expected.eql(x));
    var exp_secp_p = try Int.initSet(std.testing.allocator, secp_utils.SECP_P_V2);
    defer exp_secp_p.deinit();

    try std.testing.expect(exp_secp_p.eql(secp_p));
}

test "VrfPack: is zero pack ed25519 with zero" {
    var tmp = try Int.initSet(std.testing.allocator, 0);
    defer tmp.deinit();

    try assertIsZeroPackEd25519Equals(0, 0, 0, tmp);
}

test "VrfPack: is zero pack ed25519 with secp prime minus one" {
    var tmp = try Int.initSet(std.testing.allocator, secp_utils.SECP_P_V2 - 1);
    defer tmp.deinit();

    try assertIsZeroPackEd25519Equals(SECP_P_D0 - 1, SECP_P_D1, SECP_P_D2, tmp);
}

test "VrfPack: is zero pack ed25519 with secp prime" {
    var tmp = try Int.initSet(std.testing.allocator, 0);
    defer tmp.deinit();

    try assertIsZeroPackEd25519Equals(SECP_P_D0, SECP_P_D1, SECP_P_D2, tmp);
}

test "VrfPack: reduce ed25519 with zero" {
    var tmp = try Int.initSet(std.testing.allocator, 0);
    defer tmp.deinit();

    try assertIsZeroPackEd25519Equals(0, 0, 0, tmp);
}

test "VrfPack: reduce ed25519 with prime minus one" {
    var tmp = try Int.initSet(std.testing.allocator, secp_utils.SECP_P_V2 - 1);
    defer tmp.deinit();

    try assertIsZeroPackEd25519Equals(SECP_P_D0 - 1, SECP_P_D1, SECP_P_D2, tmp);
}

test "VrfPack: reduce ed25519 with prime" {
    var tmp = try Int.initSet(std.testing.allocator, 0);
    defer tmp.deinit();

    try assertIsZeroPackEd25519Equals(SECP_P_D0, SECP_P_D1, SECP_P_D2, tmp);
}

test "VrfPack: is zero assign scope vars ed25519 with one" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{});
    defer ids_data.deinit();

    vm.run_context.fp.* = 0;

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = try Int.initSet(std.testing.allocator, 1) });

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.IS_ZERO_ASSIGN_SCOPE_VARS_ED25519,
        undefined,
        &exec_scopes,
    );

    const x = try exec_scopes.getValue(Int, "x_inv");
    const value = try exec_scopes.getValue(Int, "value");
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    var expected = try Int.initSet(std.testing.allocator, 1);
    defer expected.deinit();

    try std.testing.expect(expected.eql(x));
    try std.testing.expect(expected.eql(value));

    var exp_secp_p = try Int.initSet(std.testing.allocator, secp_utils.SECP_P_V2);
    defer exp_secp_p.deinit();

    try std.testing.expect(exp_secp_p.eql(secp_p));
}
