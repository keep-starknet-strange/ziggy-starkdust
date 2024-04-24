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

/// Implements hint:
/// ```python
/// def split(num: int, num_bits_shift: int, length: int):
///     a = []
///     for _ in range(length):
///         a.append( num & ((1 << num_bits_shift) - 1) )
///         num = num >> num_bits_shift
///     return tuple(a)
///
/// def pack(z, num_bits_shift: int) -> int:
///     limbs = (z.low, z.high)
///     return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
///
/// def pack_extended(z, num_bits_shift: int) -> int:
///     limbs = (z.d0, z.d1, z.d2, z.d3)
///     return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
///
/// x = pack_extended(ids.x, num_bits_shift = 128)
/// div = pack(ids.div, num_bits_shift = 128)
///
/// quotient, remainder = divmod(x, div)
///
/// quotient_split = split(quotient, num_bits_shift=128, length=4)
///
/// ids.quotient.d0 = quotient_split[0]
/// ids.quotient.d1 = quotient_split[1]
/// ids.quotient.d2 = quotient_split[2]
/// ids.quotient.d3 = quotient_split[3]
///
/// remainder_split = split(remainder, num_bits_shift=128, length=2)
/// ids.remainder.low = remainder_split[0]
/// ids.remainder.high = remainder_split[1]
/// ```
pub fn uint512UnsignedDivRem(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var x = try (try Uint512.fromVarName("x", vm, ids_data, ap_tracking)).pack(allocator);
    defer x.deinit();

    var div = try (try Uint256.fromVarName("div", vm, ids_data, ap_tracking)).pack(allocator);
    defer div.deinit();

    // Main logic:
    //  quotient, remainder = divmod(x, div)
    if (div.eqlZero())
        return MathError.DividedByZero;

    var quotient = try Int.init(allocator);
    defer quotient.deinit();

    var remainder = try Int.init(allocator);
    defer remainder.deinit();

    try quotient.divTrunc(&remainder, &x, &div);

    try (try Uint512.split(allocator, quotient)).insertFromVarName(allocator, "quotient", vm, ids_data, ap_tracking);
    try (try Uint256.split(allocator, remainder)).insertFromVarName(allocator, "remainder", vm, ids_data, ap_tracking);
}

/// Implements hint:
/// ```python
/// from starkware.python.math_utils import div_mod
/// def split(a: int):
/// return (a & ((1 << 128) - 1), a >> 128)
///
/// def pack(z, num_bits_shift: int) -> int:
/// limbs = (z.low, z.high)
/// return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
///
/// a = pack(ids.a, 128)
/// b = pack(ids.b, 128)
/// p = pack(ids.p, 128)
/// # For python3.8 and above the modular inverse can be computed as follows:
/// # b_inverse_mod_p = pow(b, -1, p)
/// # Instead we use the python3.7-friendly function div_mod from starkware.python.math_utils
/// b_inverse_mod_p = div_mod(1, b, p)
///
/// b_inverse_mod_p_split = split(b_inverse_mod_p)
///
/// ids.b_inverse_mod_p.low = b_inverse_mod_p_split[0]
/// ids.b_inverse_mod_p.high = b_inverse_mod_p_split[1]
/// ```
pub fn invModPUint256(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var b = try (try Uint256.fromVarName("b", vm, ids_data, ap_tracking)).pack(allocator);
    defer b.deinit();

    var p = try (try Uint256.fromVarName("p", vm, ids_data, ap_tracking)).pack(allocator);
    defer p.deinit();

    var one = try Int.initSet(allocator, 1);
    defer one.deinit();

    var x_inverse_mod_p = try helper.divModBigInt(allocator, &one, &b, &p);
    defer x_inverse_mod_p.deinit();

    var x_inverse_mod_p_felt = try fromBigInt(allocator, x_inverse_mod_p);
    if (!x_inverse_mod_p.isPositive())
        x_inverse_mod_p_felt = x_inverse_mod_p_felt.neg();

    try Uint256.fromFelt(x_inverse_mod_p_felt).insertFromVarName(allocator, "b_inverse_mod_p", vm, ids_data, ap_tracking);
}

test "Fq: uint512 unsigned div rem ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "x", 0 },          .{ "div", 4 }, .{ "quotient", 6 },
        .{ "remainder", 10 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{2363463} },
        .{ .{ 1, 1 }, .{566795} },
        .{ .{ 1, 2 }, .{8760799} },
        .{ .{ 1, 3 }, .{62362634} },
        .{ .{ 1, 4 }, .{8340843} },
        .{ .{ 1, 5 }, .{124152} },
    });

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.UINT512_UNSIGNED_DIV_REM,
        undefined,
        &exec_scopes,
    );

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 6 }, .{158847186690949537631480225217589612243} },
        .{ .{ 1, 7 }, .{105056890940778813909974456334651647691} },
        .{ .{ 1, 8 }, .{502} },
        .{ .{ 1, 9 }, .{0} },
        .{ .{ 1, 10 }, .{235556430256711128858231095164527378198} },
        .{ .{ 1, 11 }, .{83573} },
    });
}

test "Fq: uint512 unsigned div rem div is zero" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "x", 0 },          .{ "div", 4 }, .{ "quotient", 6 },
        .{ "remainder", 10 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{2363463} },
        .{ .{ 1, 1 }, .{566795} },
        .{ .{ 1, 2 }, .{8760799} },
        .{ .{ 1, 3 }, .{62362634} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
    });

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try std.testing.expectError(MathError.DividedByZero, testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.UINT512_UNSIGNED_DIV_REM,
        undefined,
        &exec_scopes,
    ));
}

test "Fq: inv mod p uint256 ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", 0 },               .{ "b", 2 }, .{ "p", 4 },
        .{ "b_inverse_mod_p", 6 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{2363463} },
        .{ .{ 1, 1 }, .{566795} },
        .{ .{ 1, 2 }, .{8760799} },
        .{ .{ 1, 3 }, .{62362634} },
        .{ .{ 1, 4 }, .{8340842} },
        .{ .{ 1, 5 }, .{124152} },
    });

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.INV_MOD_P_UINT256,
        undefined,
        &exec_scopes,
    );

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 6 }, .{320134454404400884259649806286603992559} },
        .{ .{ 1, 7 }, .{106713} },
    });
}

test "Fq: inv mod p uint256 igcdex not 1" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", 0 },               .{ "b", 2 }, .{ "p", 4 },
        .{ "b_inverse_mod_p", 6 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{2363463} },
        .{ .{ 1, 1 }, .{566795} },
        .{ .{ 1, 2 }, .{1} },
        .{ .{ 1, 3 }, .{1} },
        .{ .{ 1, 4 }, .{1} },
        .{ .{ 1, 5 }, .{1} },
    });

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try std.testing.expectError(MathError.DivModIgcdexNotZero, testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.INV_MOD_P_UINT256,
        undefined,
        &exec_scopes,
    ));
}
