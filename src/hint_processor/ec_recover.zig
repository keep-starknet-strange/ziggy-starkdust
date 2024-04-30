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
const HintType = @import("../vm/types/execution_scopes.zig").HintType;

const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

const bigint_utils = @import("builtin_hint_processor/secp/bigint_utils.zig");

const BigInt3 = bigint_utils.BigInt3;
const Int = @import("std").math.big.int.Managed;

// Implements Hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import pack
//     from starkware.python.math_utils import div_mod, safe_div

//     N = pack(ids.n, PRIME)
//     x = pack(ids.x, PRIME) % N
//     s = pack(ids.s, PRIME) % N,
//     value = res = div_mod(x, s, N)
// %}
pub fn ecRecoverDivmodNPacked(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var n = try (try BigInt3.fromVarName("n", vm, ids_data, ap_tracking)).pack86(allocator);
    defer n.deinit();

    if (n.eqlZero())
        return MathError.DividedByZero;

    var x = try (try BigInt3.fromVarName("x", vm, ids_data, ap_tracking))
        .pack86(allocator);
    defer x.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.divFloor(&x, &x, &n);

    var s = try (try BigInt3.fromVarName("s", vm, ids_data, ap_tracking))
        .pack86(allocator);
    defer s.deinit();

    try tmp.divFloor(&s, &s, &n);

    var value = try helper.divModBigInt(allocator, &x, &s, &n);
    errdefer value.deinit();

    var res = try value.clone();
    errdefer res.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("res", .{ .big_int = res });
}

// Implements Hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import pack
//     from starkware.python.math_utils import div_mod, safe_div

//     a = pack(ids.x, PRIME)
//     b = pack(ids.s, PRIME)
//     value = res = a - b
// %}
pub fn ecRecoverSubAB(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var a = try (try BigInt3.fromVarName("a", vm, ids_data, ap_tracking)).pack86(allocator);
    defer a.deinit();

    var b = try (try BigInt3.fromVarName("b", vm, ids_data, ap_tracking)).pack86(allocator);
    defer b.deinit();

    var value = try Int.init(allocator);
    errdefer value.deinit();

    try value.sub(&a, &b);

    var res = try value.clone();
    errdefer res.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("res", .{ .big_int = res });
}

// Implements Hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import pack
//     from starkware.python.math_utils import div_mod, safe_div

//     a = pack(ids.a, PRIME)
//     b = pack(ids.b, PRIME)
//     product = a * b
//     m = pack(ids.m, PRIME)

//     value = res = product % m
// %}
pub fn ecRecoverProductMod(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var a = try (try BigInt3.fromVarName("a", vm, ids_data, ap_tracking)).pack86(allocator);
    defer a.deinit();

    var b = try (try BigInt3.fromVarName("b", vm, ids_data, ap_tracking)).pack86(allocator);
    defer b.deinit();

    var m = try (try BigInt3.fromVarName("m", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer m.deinit();

    if (m.eqlZero())
        return MathError.DividedByZero;

    var product = try Int.init(allocator);
    errdefer product.deinit();

    try product.mul(&a, &b);

    var value = try Int.init(allocator);
    errdefer value.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.divFloor(&value, &product, &m);

    var res = try value.clone();
    errdefer res.deinit();

    try exec_scopes.assignOrUpdateVariable("product", .{ .big_int = product });
    try exec_scopes.assignOrUpdateVariable("m", .{ .big_int = m });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("res", .{ .big_int = res });
}

// Implements Hint:
// %{
//     value = k = product // m
// %}
pub fn ecRecoverProductDivM(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    const product = try exec_scopes.getValue(Int, "product");
    const m = try exec_scopes.getValue(Int, "m");

    if (m.eqlZero())
        return MathError.DividedByZero;

    var value = try Int.init(allocator);
    errdefer value.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try value.divFloor(&tmp, &product, &m);

    var k = try value.clone();
    errdefer k.deinit();

    try exec_scopes.assignOrUpdateVariable("k", .{ .big_int = k });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
}

test "EcRecover: runEcRecoverDivmodNIsZero" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    vm.run_context.fp = 8;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{ .{ "n", -8 }, .{ "x", -5 }, .{ "s", -2 } });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{25} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
        .{ .{ 1, 6 }, .{5} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    try std.testing.expectError(MathError.DividedByZero, testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.EC_RECOVER_DIV_MOD_N_PACKED, undefined, &exec_scopes));
}

test "EcRecover: runEcRecoverDivmodN ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    vm.run_context.fp = 8;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{ .{ "n", -8 }, .{ "x", -5 }, .{ "s", -2 } });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{177} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{25} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
        .{ .{ 1, 6 }, .{5} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.EC_RECOVER_DIV_MOD_N_PACKED, undefined, &exec_scopes);

    var expected = try Int.initSet(std.testing.allocator, 5);
    defer expected.deinit();

    try std.testing.expect(
        expected.eql(try exec_scopes.getValue(Int, "value")),
    );

    try std.testing.expect(
        expected.eql(try exec_scopes.getValue(Int, "res")),
    );
}

test "EcRecover: ecRecoverSubAB ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    vm.run_context.fp = 8;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -8 },
        .{ "b", -5 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{100} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{25} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.EC_RECOVER_SUB_A_B, undefined, &exec_scopes);

    var expected = try Int.initSet(std.testing.allocator, 75);
    defer expected.deinit();

    try std.testing.expect(
        expected.eql(try exec_scopes.getValue(Int, "value")),
    );

    try std.testing.expect(
        expected.eql(try exec_scopes.getValue(Int, "res")),
    );
}

test "EcRecover: ecRecoverProductMod ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    vm.run_context.fp = 8;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -8 },
        .{ "b", -5 },
        .{ "m", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{60} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{2} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
        .{ .{ 1, 6 }, .{100} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.EC_RECOVER_PRODUCT_MOD, undefined, &exec_scopes);

    var expectedValue = try Int.initSet(std.testing.allocator, 20);
    defer expectedValue.deinit();

    var expectedProduct = try Int.initSet(std.testing.allocator, 120);
    defer expectedProduct.deinit();

    var expectedM = try Int.initSet(std.testing.allocator, 100);
    defer expectedM.deinit();

    try std.testing.expect(
        expectedValue.eql(try exec_scopes.getValue(Int, "value")),
    );

    try std.testing.expect(
        expectedValue.eql(try exec_scopes.getValue(Int, "res")),
    );

    try std.testing.expect(
        expectedProduct.eql(try exec_scopes.getValue(Int, "product")),
    );

    try std.testing.expect(
        expectedM.eql(try exec_scopes.getValue(Int, "m")),
    );
}

test "EcRecover: ecRecoverProductMod zero" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    vm.run_context.fp = 8;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -8 },
        .{ "b", -5 },
        .{ "m", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{60} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{2} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
        .{ .{ 1, 6 }, .{0} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    try std.testing.expectError(MathError.DividedByZero, testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.EC_RECOVER_PRODUCT_MOD, undefined, &exec_scopes));
}

test "EcRecover: ecRecoverProductDivM ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("product", .{ .big_int = try Int.initSet(std.testing.allocator, 250) });
    try exec_scopes.assignOrUpdateVariable("m", .{ .big_int = try Int.initSet(std.testing.allocator, 100) });

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"none"});
    defer ids_data.deinit();

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.EC_RECOVER_PRODUCT_DIV_M, undefined, &exec_scopes);

    var expectedValue = try Int.initSet(std.testing.allocator, 2);
    defer expectedValue.deinit();

    try std.testing.expect(
        expectedValue.eql(try exec_scopes.getValue(Int, "value")),
    );

    try std.testing.expect(
        expectedValue.eql(try exec_scopes.getValue(Int, "k")),
    );
}

test "EcRecover: ecRecoverProductDivM zero" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("product", .{ .big_int = try Int.initSet(std.testing.allocator, 250) });
    try exec_scopes.assignOrUpdateVariable("m", .{ .big_int = try Int.initSet(std.testing.allocator, 0) });

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"none"});
    defer ids_data.deinit();

    try std.testing.expectError(MathError.DividedByZero, testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.EC_RECOVER_PRODUCT_DIV_M, undefined, &exec_scopes));
}
