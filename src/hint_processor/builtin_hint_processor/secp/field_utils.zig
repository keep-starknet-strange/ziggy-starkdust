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

const BigInt3 = bigint_utils.BigInt3;
const Uint384 = bigint_utils.Uint384;
const Int = @import("std").math.big.int.Managed;

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

//     q, r = divmod(pack(ids.val, PRIME), SECP_P)
//     assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
//     ids.q = q % PRIME
// %}
pub fn verifyZero(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    secp_p_comp: anytype,
) !void {
    var secp_p = try Int.initSet(allocator, secp_p_comp);
    defer secp_p.deinit();

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = try secp_p.clone() });
    var val = try (try Uint384.fromVarName("val", vm, ids_data, ap_tracking)).pack86(allocator);
    defer val.deinit();

    var q = try Int.init(allocator);
    defer q.deinit();

    var r = try Int.init(allocator);
    defer r.deinit();

    try q.divTrunc(&r, &val, &secp_p);

    if (!r.eqlZero())
        return HintError.SecpVerifyZero;

    try hint_utils.insertValueFromVarName(allocator, "q", MaybeRelocatable.fromFelt(try fromBigInt(allocator, q)), vm, ids_data, ap_tracking);
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import pack

//     q, r = divmod(pack(ids.val, PRIME), SECP_P)
//     assert r == 0, f"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}."
//     ids.q = q % PRIME
// %}
pub fn verifyZeroWithExternalConst(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    var val = try (try Uint384.fromVarName("val", vm, ids_data, ap_tracking)).pack86(allocator);
    defer val.deinit();

    var q = try Int.init(allocator);
    defer q.deinit();

    var r = try Int.init(allocator);
    defer r.deinit();

    try q.divTrunc(&r, &val, &secp_p);

    if (!r.eqlZero())
        return HintError.SecpVerifyZero;

    try hint_utils.insertValueFromVarName(allocator, "q", MaybeRelocatable.fromFelt(try fromBigInt(allocator, q)), vm, ids_data, ap_tracking);
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

//     value = pack(ids.x, PRIME) % SECP_P
// %}
pub fn reduceV1(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var secp_p = try Int.initSet(allocator, secp_utils.SECP_P);
    defer secp_p.deinit();

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = try secp_p.clone() });

    var value = try (try Uint384.fromVarName("x", vm, ids_data, ap_tracking)).pack86(allocator);
    defer value.deinit();

    var tmp = try Int.init(allocator);
    errdefer tmp.deinit();

    try value.divFloor(&tmp, &value, &secp_p);

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = tmp });
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import pack
//     value = pack(ids.x, PRIME) % SECP_P
// %}
pub fn reduceV2(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    var value = try (try Uint384.fromVarName("x", vm, ids_data, ap_tracking)).pack86(allocator);
    defer value.deinit();

    var result = try Int.init(allocator);
    errdefer result.deinit();

    try value.divFloor(&result, &value, &secp_p);

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = result });
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

//     x = pack(ids.x, PRIME) % SECP_P
// %}
pub fn isZeroPack(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var secp_p = try Int.initSet(allocator, secp_utils.SECP_P);
    defer secp_p.deinit();

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = try secp_p.clone() });

    var x_packed = try (try Uint384.fromVarName("x", vm, ids_data, ap_tracking)).pack86(allocator);
    defer x_packed.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var result = try Int.init(allocator);
    errdefer result.deinit();

    try tmp.divFloor(&result, &x_packed, &secp_p);

    try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = result });
}

pub fn isZeroPackExternalSecp(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    var x_packed = try (try Uint384.fromVarName("x", vm, ids_data, ap_tracking)).pack86(allocator);
    defer x_packed.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var result = try Int.init(allocator);
    errdefer result.deinit();

    try tmp.divFloor(&result, &x_packed, &secp_p);

    try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = result });
}

// Implements hint:
// in .cairo program
// if nondet %{ x == 0 %} != 0:

// On .json compiled program
// "memory[ap] = to_felt_or_relocatable(x == 0)"
pub fn isZeroNondet(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
) !void {
    //Get `x` variable from vm scope
    const x = try exec_scopes.getValue(Int, "x");

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromInt(u8, if (x.eqlZero()) 1 else 0));
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P
//     from starkware.python.math_utils import div_mod

//     value = x_inv = div_mod(1, x, SECP_P)
// %}
pub fn isZeroAssignScopeVariables(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    var secp_p = try Int.initSet(allocator, secp_utils.SECP_P);
    defer secp_p.deinit();

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = try secp_p.clone() });
    //Get `x` variable from vm scope
    const x = try exec_scopes.getValue(Int, "x");

    var tmp = try Int.initSet(allocator, 1);
    defer tmp.deinit();

    var value = try field_helper.divModBigInt(allocator, &tmp, &x, &secp_p);

    {
        errdefer value.deinit();
        try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    }

    try exec_scopes.assignOrUpdateVariable("x_inv", .{ .big_int = try value.clone() });
}

// Implements hint:
// %{
//     from starkware.python.math_utils import div_mod

//     value = x_inv = div_mod(1, x, SECP_P)
// %}
pub fn isZeroAssignScopeVariablesExternalConst(
    allocator: std.mem.Allocator,
    exec_scopes: *ExecutionScopes,
) !void {
    //Get variables from vm scope
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");
    const x = try exec_scopes.getValue(Int, "x");

    var tmp = try Int.initSet(allocator, 1);
    defer tmp.deinit();

    var value = try field_helper.divModBigInt(allocator, &tmp, &x, &secp_p);

    {
        errdefer value.deinit();
        try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    }

    try exec_scopes.assignOrUpdateVariable("x_inv", .{ .big_int = try value.clone() });
}

test "SecpFieldUtils: verify zero ok" {
    const hint_code: []const []const u8 = &.{
        hint_codes.VERIFY_ZERO_V1,
        hint_codes.VERIFY_ZERO_V2,
        hint_codes.VERIFY_ZERO_V3,
    };

    for (hint_code) |code| {
        var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        try vm.segments.memory.setUpMemory(
            std.testing.allocator,
            .{
                .{ .{ 1, 4 }, .{0} },
                .{ .{ 1, 5 }, .{0} },
                .{ .{ 1, 6 }, .{0} },
            },
        );

        //Initialize fp
        vm.run_context.pc.* = Relocatable.init(0, 0);
        vm.run_context.ap.* = 9;
        vm.run_context.fp.* = 9;
        //Create hint_data

        var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
            .{ "val", -5 },
            .{ "q", 0 },
        });
        defer ids_data.deinit();

        var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
        defer exec_scopes.deinit();

        //Execute the hint
        try testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            code,
            undefined,
            &exec_scopes,
        );

        try testing_utils.checkMemory(vm.segments.memory, .{
            .{ .{ 1, 9 }, .{0} },
        });
    }
}

test "SecpFieldUtils: verify zero v3 ok" {
    const hint_code: []const []const u8 = &.{
        "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\n\nq, r = divmod(pack(ids.val, PRIME), SECP_P)\nassert r == 0, f\"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}.\"\nids.q = q % PRIME",
        "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P\nq, r = divmod(pack(ids.val, PRIME), SECP_P)\nassert r == 0, f\"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}.\"\nids.q = q % PRIME",
    };

    for (hint_code) |code| {
        var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        try vm.segments.memory.setUpMemory(
            std.testing.allocator,
            .{
                .{ .{ 1, 4 }, .{0} },
                .{ .{ 1, 5 }, .{0} },
                .{ .{ 1, 6 }, .{0} },
            },
        );

        //Initialize fp
        vm.run_context.pc.* = Relocatable.init(0, 0);
        vm.run_context.ap.* = 9;
        vm.run_context.fp.* = 9;
        //Create hint_data

        var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
            .{ "val", -5 },
            .{ "q", 0 },
        });
        defer ids_data.deinit();

        var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
        defer exec_scopes.deinit();

        //Execute the hint
        try testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            code,
            undefined,
            &exec_scopes,
        );

        try testing_utils.checkMemory(vm.segments.memory, .{
            .{ .{ 1, 9 }, .{0} },
        });
    }
}

test "SecpFieldUtils: verify zero external const ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import pack\n\nq, r = divmod(pack(ids.val, PRIME), SECP_P)\nassert r == 0, f\"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}.\"\nids.q = q % PRIME";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.pc.* = Relocatable.init(0, 0);
    vm.run_context.ap.* = 9;
    vm.run_context.fp.* = 9;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{55} },
        .{ .{ 1, 5 }, .{0} },
        .{ .{ 1, 6 }, .{0} },
    });

    //Create hint_data
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "val", -5 },
        .{ "q", 0 },
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    {
        var secp_p = try Int.initSet(std.testing.allocator, 55);
        errdefer secp_p.deinit();

        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 9 }, .{1} },
    });
}

test "SecpFieldUtils: verify zero error" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\n\nq, r = divmod(pack(ids.val, PRIME), SECP_P)\nassert r == 0, f\"verify_zero: Invalid input {ids.val.d0, ids.val.d1, ids.val.d2}.\"\nids.q = q % PRIME";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.addMemorySegment();

    //Initialize fp
    vm.run_context.pc.* = Relocatable.init(0, 0);
    vm.run_context.ap.* = 9;
    vm.run_context.fp.* = 9;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
        .{ .{ 1, 6 }, .{150} },
    });

    //Create hint_data
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "val", -5 },
        .{ "q", 0 },
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try std.testing.expectError(HintError.SecpVerifyZero, testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    ));
}

test "SecpFieldUtils: reduce ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\n\nvalue = pack(ids.x, PRIME) % SECP_P";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 20 }, .{132181232131231239112312312313213083892150} },
        .{ .{ 1, 21 }, .{10} },
        .{ .{ 1, 22 }, .{10} },
    });

    //Initialize fp
    vm.run_context.fp.* = 25;
    //Create hint_data

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{.{ "x", -5 }});
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");

    var exp_value = try Int.initSet(std.testing.allocator, 59863107065205964761754162760883789350782881856141750);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
}

test "SecpFieldUtils: reduce error" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\n\nvalue = pack(ids.x, PRIME) % SECP_P";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.segments.addSegment();

    //Initialize fp
    vm.run_context.fp.* = 25;
    //Create hint_data

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{.{ "x", -5 }});
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try std.testing.expectError(HintError.IdentifierHasNoMember, testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    ));
}

test "SecpFieldUtils: reduceV2 ok" {
    const hint_code = hint_codes.REDUCE_V2;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    inline for (0..3) |_| _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 20 }, .{132181232131231239112312312313213083892150} },
        .{ .{ 1, 21 }, .{12354812987893128791212331231233} },
        .{ .{ 1, 22 }, .{654867675805132187} },
    });

    //Initialize fp
    vm.run_context.fp.* = 25;
    //Create hint_data

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{.{ "x", -5 }});
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    {
        var secp_p = try Int.initSet(std.testing.allocator, secp_utils.SECP_P);
        errdefer secp_p.deinit();
        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }
    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");

    var exp_value = try Int.initSet(std.testing.allocator, 3920241379018821570896271640300310233395357371896837069219347149797814);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
}

test "SecpFieldUtils: is zero pack ok" {
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    const hint_code: []const []const u8 = &.{
        hint_codes.IS_ZERO_PACK_V1,
        hint_codes.IS_ZERO_PACK_V2,
        hint_codes.IS_ZERO_PACK_EXTERNAL_SECP_V1,
        hint_codes.IS_ZERO_PACK_EXTERNAL_SECP_V2,
    };

    for (hint_code) |code| {
        var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        try vm.segments.memory.setUpMemory(
            std.testing.allocator,
            .{
                .{ .{ 1, 10 }, .{232113757366008801543585} },
                .{ .{ 1, 11 }, .{232113757366008801543585} },
                .{ .{ 1, 12 }, .{232113757366008801543585} },
            },
        );

        //Initialize fp
        vm.run_context.fp.* = 15;
        //Create hint_data

        var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
        defer ids_data.deinit();

        try ids_data.put("x", HintReference.initSimple(-5));

        //Execute the hint
        try testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            code,
            undefined,
            &exec_scopes,
        );

        const x = try exec_scopes.getValue(Int, "x");
        var exp_x = try Int.initSet(std.testing.allocator, 1389505070847794345082847096905107459917719328738389700703952672838091425185);
        defer exp_x.deinit();

        try std.testing.expect(exp_x.eql(x));
    }
}

test "SecpFieldUtils: is zero nondet ok true" {
    const hint_code: []const []const u8 = &.{
        hint_codes.IS_ZERO_NONDET,
        hint_codes.IS_ZERO_INT,
    };

    for (hint_code) |code| {
        var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        inline for (0..2) |_| _ = try vm.addMemorySegment();

        var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
        defer exec_scopes.deinit();

        {
            var x = try Int.initSet(std.testing.allocator, 0);
            errdefer x.deinit();

            try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = x });
        }

        //Initialize fp
        vm.run_context.ap.* = 15;
        //Create hint_data

        var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
        defer ids_data.deinit();

        //Execute the hint
        try testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            code,
            undefined,
            &exec_scopes,
        );

        try testing_utils.checkMemory(vm.segments.memory, .{
            .{ .{ 1, 15 }, .{1} },
        });
    }
}

test "SecpFieldUtils: is zero nondet ok false" {
    const hint_code: []const []const u8 = &.{
        hint_codes.IS_ZERO_NONDET,
        hint_codes.IS_ZERO_INT,
    };

    for (hint_code) |code| {
        var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        inline for (0..2) |_| _ = try vm.addMemorySegment();

        var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
        defer exec_scopes.deinit();

        {
            var x = try Int.initSet(std.testing.allocator, 123890);
            errdefer x.deinit();

            try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = x });
        }

        //Initialize fp
        vm.run_context.ap.* = 15;
        //Create hint_data

        var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
        defer ids_data.deinit();

        //Execute the hint
        try testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            code,
            undefined,
            &exec_scopes,
        );

        try testing_utils.checkMemory(vm.segments.memory, .{
            .{ .{ 1, 15 }, .{0} },
        });
    }
}

test "SecpFieldUtils: is zero assign scope variables ok" {
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    const hint_code: []const []const u8 = &.{
        hint_codes.IS_ZERO_ASSIGN_SCOPE_VARS,
        hint_codes.IS_ZERO_ASSIGN_SCOPE_VARS_EXTERNAL_SECP,
    };

    for (hint_code) |code| {
        var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        {
            var x = try Int.initSet(std.testing.allocator, 52621538839140286024584685587354966255185961783273479086367);
            errdefer x.deinit();

            try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = x });
        }

        //Create hint_data
        var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
        defer ids_data.deinit();

        //Execute the hint
        try testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            code,
            undefined,
            &exec_scopes,
        );

        var exp_val = try Int.initSet(std.testing.allocator, 19429627790501903254364315669614485084365347064625983303617500144471999752609);
        defer exp_val.deinit();

        const act_val = try exec_scopes.getValue(Int, "value");
        const x_inv = try exec_scopes.getValue(Int, "x_inv");

        try std.testing.expect(exp_val.eql(act_val));
        try std.testing.expect(exp_val.eql(x_inv));
    }
}
