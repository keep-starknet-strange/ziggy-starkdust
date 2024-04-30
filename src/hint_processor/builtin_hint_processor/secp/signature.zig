const std = @import("std");

const testing_utils = @import("../../testing_utils.zig");
const CoreVM = @import("../../../vm/core.zig");
const field_helper = @import("../../../math/fields/helper.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const fromBigInt = @import("../../../math/fields/starknet.zig").fromBigInt;
const MaybeRelocatable = @import("../../../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../../../vm/memory/relocatable.zig").Relocatable;
const CairoVM = CoreVM.CairoVM;
const hint_utils = @import("../../hint_utils.zig");
const HintReference = @import("../../hint_processor_def.zig").HintReference;
const hint_codes = @import("../../builtin_hint_codes.zig");
const Allocator = std.mem.Allocator;
const ApTracking = @import("../../../vm/types/programjson.zig").ApTracking;
const ExecutionScopes = @import("../../../vm/types/execution_scopes.zig").ExecutionScopes;

const MathError = @import("../../../vm/error.zig").MathError;
const HintError = @import("../../../vm/error.zig").HintError;
const CairoVMError = @import("../../../vm/error.zig").CairoVMError;

const bigint_utils = @import("bigint_utils.zig");
const secp_utils = @import("secp_utils.zig");

const Uint384 = bigint_utils.Uint384;
const BigInt3 = bigint_utils.BigInt3;
const Int = @import("std").math.big.int.Managed;

// Implements hint:
// from starkware.cairo.common.cairo_secp.secp_utils import N, pack
// from starkware.python.math_utils import div_mod, safe_div

// a = pack(ids.a, PRIME)
// b = pack(ids.b, PRIME)
// value = res = div_mod(a, b, N)
pub fn divModNPacked(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    n: Int,
) !void {
    var a = try (try Uint384.fromVarName("a", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer a.deinit();

    var b = try (try Uint384.fromVarName("b", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer b.deinit();

    var value = try field_helper.divModBigInt(allocator, &a, &b, &n);
    errdefer value.deinit();

    try exec_scopes.assignOrUpdateVariable("a", .{ .big_int = a });
    try exec_scopes.assignOrUpdateVariable("b", .{ .big_int = b });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("res", .{ .big_int = try value.clone() });
}

pub fn divModNPackedDivmod(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var n = try Int.initSet(allocator, secp_utils.N);
    defer n.deinit();

    try exec_scopes.assignOrUpdateVariable("N", .{ .big_int = try n.clone() });

    try divModNPacked(allocator, vm, exec_scopes, ids_data, ap_tracking, n);
}

pub fn divModNPackedExternalN(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const n = try exec_scopes.getValue(Int, "N");
    try divModNPacked(allocator, vm, exec_scopes, ids_data, ap_tracking, n);
}

// Implements hint:
// value = k = safe_div(res * b - a, N)
pub fn divModNSafeDiv(
    allocator: std.mem.Allocator,
    exec_scopes: *ExecutionScopes,
    a_alias: []const u8,
    b_alias: []const u8,
    to_add: u64,
) !void {
    const a = try exec_scopes.getValue(Int, a_alias);
    const b = try exec_scopes.getValue(Int, b_alias);
    const res = try exec_scopes.getValue(Int, "res");

    const n = try exec_scopes.getValue(Int, "N");

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.mul(&res, &b);
    try tmp.sub(&tmp, &a);

    var value = try field_helper.safeDivBigIntV2(allocator, tmp, n);
    errdefer value.deinit();

    try value.addScalar(&value, to_add);

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

//     x_cube_int = pack(ids.x_cube, PRIME) % SECP_P
//     y_square_int = (x_cube_int + ids.BETA) % SECP_P
//     y = pow(y_square_int, (SECP_P + 1) // 4, SECP_P)

//     # We need to decide whether to take y or SECP_P - y.
//     if ids.v % 2 == y % 2:
//         value = y
//     else:
//         value = (-y) % SECP_P
// %}
pub fn getPointFromX(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    var secp_p = try Int.initSet(allocator, secp_utils.SECP_P);

    {
        errdefer secp_p.deinit();
        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }

    var beta = try (constants.get(secp_utils.BETA) orelse return HintError.MissingConstant).toSignedBigInt(allocator);
    defer beta.deinit();

    var x_cube_int = try (try Uint384.fromVarName("x_cube", vm, ids_data, ap_tracking)).pack86(allocator);
    defer x_cube_int.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.divFloor(&x_cube_int, &x_cube_int, &secp_p);

    try tmp.add(&x_cube_int, &beta);

    var y_cube_int = try Int.init(allocator);
    defer y_cube_int.deinit();

    try tmp.divFloor(&y_cube_int, &tmp, &secp_p);

    // Divide by 4
    try tmp.addScalar(&secp_p, 1);
    try tmp.shiftRight(&tmp, 2);

    var y = try field_helper.powModulusBigInt(allocator, y_cube_int, tmp, secp_p);
    errdefer y.deinit();

    var v = try (try hint_utils.getIntegerFromVarName("v", vm, ids_data, ap_tracking)).toSignedBigInt(allocator);
    defer v.deinit();

    if (v.isEven() != y.isEven()) {
        try y.sub(&secp_p, &y);
    }

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = y });
}

// Implements hint:
//    from starkware.cairo.common.cairo_secp.secp_utils import pack
//    from starkware.python.math_utils import div_mod, safe_div

//    N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141
//    x = pack(ids.x, PRIME) % N
//    s = pack(ids.s, PRIME) % N
//    value = res = div_mod(x, s, N)
pub fn packModnDivModn(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var n = try Int.initSet(allocator, secp_utils.N);
    defer n.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var x = try (try Uint384.fromVarName("x", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer x.deinit();

    try tmp.divFloor(&x, &x, &n);

    var s = try (try Uint384.fromVarName("s", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer s.deinit();

    try tmp.divFloor(&s, &s, &n);

    var value = try field_helper.divModBigInt(allocator, &x, &s, &n);
    errdefer value.deinit();

    try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = x });
    try exec_scopes.assignOrUpdateVariable("s", .{ .big_int = s });
    try exec_scopes.assignOrUpdateVariable("N", .{ .big_int = try n.clone() });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = try value.clone() });
    try exec_scopes.assignOrUpdateVariable("res", .{ .big_int = value });
}

test "SecpSignature: safe div ok" {
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    // "import N"
    var n = try Int.initSet(std.testing.allocator, secp_utils.N);

    {
        errdefer n.deinit();
        try exec_scopes.assignOrUpdateVariable("N", .{ .big_int = n });
    }

    const hint_code: []const []const u8 = &.{
        hint_codes.DIV_MOD_N_PACKED_DIVMOD_V1,
        hint_codes.DIV_MOD_N_PACKED_DIVMOD_EXTERNAL_N,
    };

    for (hint_code) |code| {
        var vm = try CairoVM.init(std.testing.allocator, .{});
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        try vm.segments.memory.setUpMemory(std.testing.allocator, .{
            .{ .{ 1, 0 }, .{15} },
            .{ .{ 1, 1 }, .{3} },
            .{ .{ 1, 2 }, .{40} },
            .{ .{ 1, 3 }, .{0} },
            .{ .{ 1, 4 }, .{10} },
            .{ .{ 1, 5 }, .{1} },
        });

        vm.run_context.fp = 3;

        var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
            .{ "a", -3 },
            .{ "b", 0 },
        });
        defer ids_data.deinit();

        try testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            code,
            undefined,
            &exec_scopes,
        );

        try divModNSafeDiv(std.testing.allocator, &exec_scopes, "a", "b", 0);
        try divModNSafeDiv(std.testing.allocator, &exec_scopes, "a", "b", 1);
    }
}

test "SecpSignature: safe div fail" {
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("a", .{ .big_int = try Int.initSet(std.testing.allocator, 0) });
    try exec_scopes.assignOrUpdateVariable("b", .{ .big_int = try Int.initSet(std.testing.allocator, 1) });
    try exec_scopes.assignOrUpdateVariable("res", .{ .big_int = try Int.initSet(std.testing.allocator, 1) });
    try exec_scopes.assignOrUpdateVariable("N", .{ .big_int = try Int.initSet(std.testing.allocator, secp_utils.N) });

    try std.testing.expectError(MathError.SafeDivFailBigInt, divModNSafeDiv(std.testing.allocator, &exec_scopes, "a", "b", 0));
}

test "SecpSignature: get point from x ok" {
    const hint_code = hint_codes.GET_POINT_FROM_X;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{18} },
            .{ .{ 1, 1 }, .{2147483647} },
            .{ .{ 1, 2 }, .{2147483647} },
            .{ .{ 1, 3 }, .{2147483647} },
        },
    );

    //Initialize fp
    vm.run_context.fp = 1;
    //Create hint_data

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "v", -1 },
        .{ "x_cube", 0 },
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(secp_utils.BETA, Felt252.fromInt(u8, 7));

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        &constants,
        &exec_scopes,
    );
}
