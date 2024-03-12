const std = @import("std");

const CoreVM = @import("../vm/core.zig");
const field_helper = @import("../math/fields/helper.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const STARKNET_PRIME = @import("../math/fields/fields.zig").STARKNET_PRIME;
const SIGNED_FELT_MAX = @import("../math/fields/fields.zig").SIGNED_FELT_MAX;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const CairoVM = CoreVM.CairoVM;
const hint_utils = @import("hint_utils.zig");
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const HintData = @import("hint_processor_def.zig").HintData;
const HintReference = @import("hint_processor_def.zig").HintReference;
const hint_codes = @import("builtin_hint_codes.zig");
const Allocator = std.mem.Allocator;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;

const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

//Implements hint:
// %{
//     from starkware.cairo.common.math_utils import assert_integer
//     assert_integer(ids.a)
//     assert 0 <= ids.a % PRIME < range_check_builtin.bound, f'a = {ids.a} is out of range.'
// %}
pub fn assertNN(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName(
        "a",
        vm,
        ids_data,
        ap_tracking,
    );

    const range_check = try vm.getRangeCheckBuiltin();

    if (range_check.bound) |bound| {
        if (a.ge(bound)) {
            return HintError.AssertNNValueOutOfRange;
        }
    }
}

pub fn isPositive(allocator: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);
    const range_check = try vm.getRangeCheckBuiltin();

    const signed_value = value.toSignedInt();

    if (range_check.bound) |bound| {
        if (@abs(signed_value) > bound.toInteger()) {
            return HintError.ValueOutsideValidRange;
        }
    }

    try hint_utils.insertValueFromVarName(allocator, "is_positive", MaybeRelocatable.fromFelt(
        if (signed_value > 0) Felt252.one() else Felt252.zero(),
    ), vm, ids_data, ap_tracking);
}

// Implements hint:from starkware.cairo.common.math.cairo
//
//	%{
//	    from starkware.cairo.common.math_utils import assert_integer
//	    assert_integer(ids.value)
//	    assert ids.value % PRIME != 0, f'assert_not_zero failed: {ids.value} = 0.'
//
// %}

pub fn assertNonZero(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);

    if (value.isZero()) return HintError.AssertNotZero;
}

pub fn verifyEcdsaSignature(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const r = try hint_utils.getIntegerFromVarName("signature_r", vm, ids_data, ap_tracking);

    const s = try hint_utils.getIntegerFromVarName("signature_s", vm, ids_data, ap_tracking);

    const ecdsa_ptr = try hint_utils.getPtrFromVarName("ecdsa_ptr", vm, ids_data, ap_tracking);

    const builtin_runner = try vm.getSignatureBuiltin();

    try builtin_runner.addSignature(ecdsa_ptr, .{
        r,
        s,
    });
}

// Implements hint:from starkware.cairo.common.math.cairo
//
//	%{
//		from starkware.crypto.signature.signature import FIELD_PRIME
//		from starkware.python.math_utils import div_mod, is_quad_residue, sqrt
//
//		x = ids.x
//		if is_quad_residue(x, FIELD_PRIME):
//		    ids.y = sqrt(x, FIELD_PRIME)
//		else:
//		    ids.y = sqrt(div_mod(x, 3, FIELD_PRIME), FIELD_PRIME)
//
// %}
pub fn isQuadResidue(
    allocator: Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    _ = ap_tracking; // autofix
    _ = vm; // autofix
    _ = ids_data; // autofix
    _ = allocator; // autofix

    // const x = try hint_utils.getIntegerFromVarName("x", vm, ids_data, ap_tracking);

    // if (x.isZero() or x.isOne()) {
    //     try hint_utils.insertValueFromVarName(allocator, "y", MaybeRelocatable.fromFelt(x), vm, ids_data, ap_tracking);
    // } else if (x.pow(Felt252.Max.div(Felt252.two()) catch unreachable).eq(Felt252.one()))) {
    //     try hint_utils.insertValueFromVarName(allocator, "y", x.sqrt() catch Felt252.zero(), vm, ids_data, ap_tracking);
    // } else {
    //     try hint_utils.insertValueFromVarName(allocator, "y", x.div(Felt252.three()).sqrt() catch Felt252.zero(), vm, ids_data, ap_tracking);
    // }
}

//Implements hint: from starkware.cairo.lang.vm.relocatable import RelocatableValue
//        both_ints = isinstance(ids.a, int) and isinstance(ids.b, int)
//        both_relocatable = (
//            isinstance(ids.a, RelocatableValue) and isinstance(ids.b, RelocatableValue) and
//            ids.a.segment_index == ids.b.segment_index)
//        assert both_ints or both_relocatable, \
//            f'assert_not_equal failed: non-comparable values: {ids.a}, {ids.b}.'
//        assert (ids.a - ids.b) % PRIME != 0, f'assert_not_equal failed: {ids.a} = {ids.b}.'
pub fn assertNotEqual(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const maybe_rel_a = try hint_utils.getMaybeRelocatableFromVarName("a", vm, ids_data, ap_tracking);
    const maybe_rel_b = try hint_utils.getMaybeRelocatableFromVarName("b", vm, ids_data, ap_tracking);

    if (!maybe_rel_a.eq(maybe_rel_b)) {
        return HintError.AssertNotEqualFail;
    }
}

//Implements hint: from starkware.python.math_utils import isqrt
//        value = ids.value % PRIME
//        assert value < 2 ** 250, f"value={value} is outside of the range [0, 2**250)."
//        assert 2 ** 250 < PRIME
//        ids.root = isqrt(value)
pub fn sqrt(
    allocator: Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const mod_value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);

    if (mod_value.gt(Felt252.two().pow(250))) {
        return HintError.ValueOutside250BitRange;
    }

    const root = Felt252.fromInt(u256, field_helper.isqrt(u256, mod_value.toInteger()) catch unreachable);

    try hint_utils.insertValueFromVarName(
        allocator,
        "root",
        MaybeRelocatable.fromFelt(root),
        vm,
        ids_data,
        ap_tracking,
    );
}

// Implements hint:

// from starkware.cairo.common.math_utils import assert_integer
// assert_integer(ids.div)
// assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
//     f'div={hex(ids.div)} is out of the valid range.'
// ids.q, ids.r = divmod(ids.value, ids.div)
pub fn unsignedDivRem(
    allocator: Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const div = try hint_utils.getIntegerFromVarName("div", vm, ids_data, ap_tracking);
    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);
    const builtin = try vm.getRangeCheckBuiltin();

    if (builtin.bound) |b| {
        if (div.isZero() or div.gt(divPrimeByBound(b))) return HintError.OutOfValidRange;
    } else if (div.isZero()) return HintError.OutOfValidRange;

    const qr = try (field_helper.divRem(u256, value.toInteger(), div.toInteger()) catch MathError.DividedByZero);

    try hint_utils.insertValueFromVarName(allocator, "r", MaybeRelocatable.fromInt(u256, qr[1]), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "q", MaybeRelocatable.fromInt(u256, qr[0]), vm, ids_data, ap_tracking);
}

fn cmpFn(context: void, a: struct { u256, u64 }, b: struct { u256, u64 }) bool {
    _ = context; // autofix
    return a[0] > b[0];
}

//  Implements hint:from starkware.cairo.common.math_utils import assert_integer
// %{
//     import itertools

//     from starkware.cairo.common.math_utils import assert_integer
//     assert_integer(ids.a)
//     assert_integer(ids.b)
//     a = ids.a % PRIME
//     b = ids.b % PRIME
//     assert a <= b, f'a = {a} is not less than or equal to b = {b}.'

//     # Find an arc less than PRIME / 3, and another less than PRIME / 2.
//     lengths_and_indices = [(a, 0), (b - a, 1), (PRIME - 1 - b, 2)]
//     lengths_and_indices.sort()
//     assert lengths_and_indices[0][0] <= PRIME // 3 and lengths_and_indices[1][0] <= PRIME // 2
//     excluded = lengths_and_indices[2][1]

//     memory[ids.range_check_ptr + 1], memory[ids.range_check_ptr + 0] = (
//         divmod(lengths_and_indices[0][0], ids.PRIME_OVER_3_HIGH))
//     memory[ids.range_check_ptr + 3], memory[ids.range_check_ptr + 2] = (
//         divmod(lengths_and_indices[1][0], ids.PRIME_OVER_2_HIGH))
// %}
pub fn assertLeFelt(
    allocator: Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const PRIME_OVER_3_HIGH = "starkware.cairo.common.math.assert_le_felt.PRIME_OVER_3_HIGH";
    const PRIME_OVER_2_HIGH = "starkware.cairo.common.math.assert_le_felt.PRIME_OVER_2_HIGH";

    const prime_over_3_high = constants
        .get(PRIME_OVER_3_HIGH) orelse return HintError.MissingConstant;
    const prime_over_2_high = constants
        .get(PRIME_OVER_2_HIGH) orelse return HintError.MissingConstant;

    const a = (try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking)).toInteger();
    const b = (try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking)).toInteger();
    const range_check_ptr = try hint_utils.getPtrFromVarName("range_check_ptr", vm, ids_data, ap_tracking);

    // TODO: use UnsignedInteger for this
    const prime_div2 = STARKNET_PRIME / 2;
    const prime_div3 = STARKNET_PRIME / 3;

    if (a > b) {
        return HintError.NonLeFelt252;
    }

    const arc1 = b - a;
    const arc2 = STARKNET_PRIME - 1 - b;

    var lengths_and_indices = [_]struct { u256, u64 }{
        .{ a, 0 },
        .{ arc1, 1 },
        .{ arc2, 2 },
    };
    inline for (0..3) |i| {
        var j = i;

        while (j > 0 and lengths_and_indices[j - 1][0] > lengths_and_indices[j][0]) : (j -= 1) {
            const tmp = lengths_and_indices[j];
            lengths_and_indices[j] = lengths_and_indices[j - 1];
            lengths_and_indices[j - 1] = tmp;
        }
    }
    // TODO: I believe this check can be removed

    if (lengths_and_indices[0][0] > prime_div3 or lengths_and_indices[1][0] > prime_div2)
        return HintError.ArcTooBig;

    const excluded = lengths_and_indices[2][1];

    try exec_scopes.assignOrUpdateVariable("excluded", .{ .felt = Felt252.fromInt(u256, excluded) });

    const qr0 = try field_helper.divModFloor(u256, lengths_and_indices[0][0], prime_over_3_high.toInteger());
    const qr1 = try field_helper.divModFloor(u256, lengths_and_indices[1][0], prime_over_2_high.toInteger());

    try vm.insertInMemory(allocator, range_check_ptr, MaybeRelocatable.fromFelt(Felt252.fromInt(u256, qr0[1])));
    try vm.insertInMemory(allocator, try range_check_ptr.addInt(1), MaybeRelocatable.fromFelt(Felt252.fromInt(u256, qr0[0])));
    try vm.insertInMemory(allocator, try range_check_ptr.addInt(2), MaybeRelocatable.fromFelt(Felt252.fromInt(u256, qr1[1])));
    try vm.insertInMemory(allocator, try range_check_ptr.addInt(3), MaybeRelocatable.fromFelt(Felt252.fromInt(u256, qr1[0])));
}

// "memory[ap] = 1 if excluded != 0 else 0"
pub fn assertLeFeltExcluded0(
    allocator: Allocator,
    vm: *CairoVM,
    exec_scopes: *const ExecutionScopes,
) !void {
    const excluded = try exec_scopes.getValue(Felt252, "excluded");

    if (!excluded.isZero()) {
        try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(Felt252.one()));
    } else {
        try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(Felt252.zero()));
    }
}

pub fn assertLeFeltExcluded1(
    allocator: Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
) !void {
    const excluded = try exec_scopes.getValue(Felt252, "excluded");

    if (!excluded.isOne()) {
        try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(Felt252.one()));
    } else {
        try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(Felt252.zero()));
    }
}

pub fn assertLeFeltExcluded2(exec_scopes: *ExecutionScopes) !void {
    const excluded = try exec_scopes.getValue(Felt252, "excluded");

    if (!excluded.equal(Felt252.fromInt(u256, 2))) {
        return HintError.ExcludedNot2;
    }
}

// Implements hint:
// %{
//     from starkware.cairo.common.math_utils import assert_integer
//     assert_integer(ids.a)
//     assert_integer(ids.b)
//     assert (ids.a % PRIME) < (ids.b % PRIME), \
//         f'a = {ids.a % PRIME} is not less than b = {ids.b % PRIME}.'
// %}
pub fn assertLtFelt(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const b = try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking);
    // Main logic
    // assert_integer(ids.a)
    // assert_integer(ids.b)
    // assert (ids.a % PRIME) < (ids.b % PRIME), \
    //     f'a = {ids.a % PRIME} is not less than b = {ids.b % PRIME}.'
    if (a.ge(b)) {
        return HintError.AssertLtFelt252;
    }
}

//Implements hint: from starkware.cairo.common.math_utils import as_int
//        # Correctness check.
//        value = as_int(ids.value, PRIME) % PRIME
//        assert value < ids.UPPER_BOUND, f'{value} is outside of the range [0, 2**250).'
//        # Calculation for the assertion.
//        ids.high, ids.low = divmod(ids.value, ids.SHIFT)
pub fn assert250Bit(
    allocator: Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const UPPER_BOUND = "starkware.cairo.common.math.assert_250_bit.UPPER_BOUND";
    const SHIFT = "starkware.cairo.common.math.assert_250_bit.SHIFT";
    //Declare constant values
    const upper_bound = constants
        .get(UPPER_BOUND) orelse try hint_utils.getConstantFromVarName("UPPER_BOUND", constants);
    const shift = constants
        .get(SHIFT) orelse try hint_utils.getConstantFromVarName("SHIFT", constants);
    var value = try hint_utils.getIntegerFromVarName(
        "value",
        vm,
        ids_data,
        ap_tracking,
    );

    value = Felt252.fromSignedInt(value.toSignedInt());

    //Main logic
    if (value.gt(upper_bound)) {
        return HintError.ValueOutside250BitRange;
    }

    const qr = try value.divRem(shift);

    try hint_utils.insertValueFromVarName(allocator, "high", MaybeRelocatable.fromFelt(qr.q), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "low", MaybeRelocatable.fromFelt(qr.r), vm, ids_data, ap_tracking);
}

//Implements hint:
// %{
//     from starkware.cairo.common.math_utils import assert_integer
//     assert ids.MAX_HIGH < 2**128 and ids.MAX_LOW < 2**128
//     assert PRIME - 1 == ids.MAX_HIGH * 2**128 + ids.MAX_LOW
//     assert_integer(ids.value)
//     ids.low = ids.value & ((1 << 128) - 1)
//     ids.high = ids.value >> 128
// %}
pub fn splitFelt(
    allocator: Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const bound = Felt252.two().pow(128);
    const max_high = try hint_utils.getConstantFromVarName("MAX_HIGH", constants);
    const max_low = try hint_utils.getConstantFromVarName("MAX_LOW", constants);

    if (!(max_high.lt(bound) and max_low.lt(bound)))
        return HintError.AssertionFailed;

    if (!Felt252.fromSignedInt(-1).equal(max_high.mul(bound).add(max_low)))
        return HintError.AssertionFailed;

    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);
    //Main logic
    //assert_integer(ids.value) (done by match)
    // ids.low = ids.value & ((1 << 128) - 1)
    // ids.high = ids.value >> 128
    const high_low = try value.divRem(bound);

    try hint_utils.insertValueFromVarName(allocator, "high", MaybeRelocatable.fromFelt(high_low.q), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "low", MaybeRelocatable.fromFelt(high_low.r), vm, ids_data, ap_tracking);
}

//Implements hint: assert ids.value == 0, 'split_int(): value is out of range.'
pub fn splitIntAssertRange(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);
    //Main logic (assert value == 0)
    if (!value.isZero()) {
        return HintError.SplitIntNotZero;
    }
}

fn divPrimeByBound(bound: Felt252) Felt252 {
    return Felt252.fromInt(u256, STARKNET_PRIME / bound.toInteger());
}

// Implements hint:

//     %{
//         from starkware.cairo.common.math_utils import as_int, assert_integer

//         assert_integer(ids.div)
//         assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
//             f'div={hex(ids.div)} is out of the valid range.'

//         assert_integer(ids.bound)
//         assert ids.bound <= range_check_builtin.bound // 2, \
//             f'bound={hex(ids.bound)} is out of the valid range.'

//         int_value = as_int(ids.value, PRIME)
//         q, ids.r = divmod(int_value, ids.div)

//         assert -ids.bound <= q < ids.bound, \
//             f'{int_value} / {ids.div} = {q} is out of the range [{-ids.bound}, {ids.bound}).'

//         ids.biased_q = q + ids.bound
//     %}
pub fn signedDivRem(
    allocator: Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const div = try hint_utils.getIntegerFromVarName("div", vm, ids_data, ap_tracking);
    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);

    const bound = try hint_utils.getIntegerFromVarName("bound", vm, ids_data, ap_tracking);
    const builtin = try vm.getRangeCheckBuiltin();

    const builtin_bound = builtin.bound orelse Felt252.Max;
    if (div.isZero() or div.gt(divPrimeByBound(builtin_bound)))
        return HintError.OutOfValidRange;

    const builtin_bound_div_2 = try builtin_bound.div(Felt252.two());
    if (bound.gt(builtin_bound_div_2))
        return HintError.OutOfValidRange;

    const int_value = value.toSignedInt();
    const int_div = div.toSignedInt();
    const int_bound = bound.toSignedInt();
    const qr = try field_helper.divModFloorSigned(int_value, int_div);

    // int_value.div_mod_floor(&int_div);

    if (@abs(int_bound) < @abs(qr[0])) {
        return HintError.OutOfValidRange;
    }

    const biased_q = qr[0] + int_bound;

    try hint_utils.insertValueFromVarName(
        allocator,
        "r",
        MaybeRelocatable.fromFelt(Felt252.fromSignedInt(qr[1])),
        vm,
        ids_data,
        ap_tracking,
    );
    try hint_utils.insertValueFromVarName(
        allocator,
        "biased_q",
        MaybeRelocatable.fromFelt(Felt252.fromSignedInt(biased_q)),
        vm,
        ids_data,
        ap_tracking,
    );
}

// importing testing utils for tests
const testing_utils = @import("testing_utils.zig");
const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;
const SignatureBuiltinRunner = @import("../vm/builtins/builtin_runner/signature.zig").SignatureBuiltinRunner;
const EcdsaInstanceDef = @import("../vm/types/ecdsa_instance_def.zig").EcdsaInstanceDef;

test "MathHints: isPositive false" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.zero().sub(Felt252.one())),
            },
        },
        .{
            .name = "is_positive",
            .elems = &.{null},
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.IS_POSITIVE, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const is_positive = try hint_utils.getIntegerFromVarName("is_positive", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.zero(), is_positive);
}

test "MathHints: isPositive true" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 17)),
            },
        },
        .{
            .name = "is_positive",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.IS_POSITIVE, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const is_positive = try hint_utils.getIntegerFromVarName("is_positive", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.one(), is_positive);
}

test "MathHints: assertNN hint ok" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 17)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NN,
        ids_data,
        .{},
    );

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
}

test "MathHints: assertNN invalid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-1)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NN,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        HintError.AssertNNValueOutOfRange,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: assertNN incorrect ids" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "incorrect_id",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-1)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NN,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        HintError.UnknownIdentifier,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: assertNN a is not integer" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromRelocatable(Relocatable.init(10, 10)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NN,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: assertNN no range check builtin" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 1)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NN,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        CairoVMError.NoRangeCheckBuiltin,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: assertNN reference is not in memory" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NN,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}
test "MathHints: assertNotZero true" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 17)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NOT_ZERO,
        ids_data,
        .{},
    );

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
}

test "MathHints: assertNotZero false" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.zero()),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_NOT_ZERO,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        HintError.AssertNotZero,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: verifyEcdsaSignature valid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    var def = EcdsaInstanceDef.init(2048);
    try vm.builtin_runners.append(.{
        .Signature = SignatureBuiltinRunner.init(std.testing.allocator, &def, true),
    });

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp.* = Relocatable.init(1, 3);
    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "signature_r",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 3086480810278599376317923499561306189851900463386393948998357832163236918254)),
            },
        },
        .{
            .name = "signature_s",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 598673427589502599949712887611119751108407514580626464031881322743364689811)),
            },
        },
        .{
            .name = "ecdsa_ptr",
            .elems = &.{
                MaybeRelocatable.fromRelocatable(.{}),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.VERIFY_ECDSA_SIGNATURE,
        ids_data,
        .{},
    );

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
}

test "MathHints: sqrt invalid negative number" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-81)),
            },
        },
        .{
            .name = "root",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SQRT, ids_data, .{});

    try std.testing.expectError(
        HintError.ValueOutside250BitRange,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: sqrt valid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 9)),
            },
        },
        .{
            .name = "root",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SQRT, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const root = try hint_utils.getIntegerFromVarName("root", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.three(), root);
}

test "MathHints: unsigned div rem success" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "div",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 7)),
            },
        },
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 15)),
            },
        },
        .{
            .name = "r",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "q",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.UNSIGNED_DIV_REM, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const q = try hint_utils.getIntegerFromVarName("q", &vm, ids_data, .{});
    const r = try hint_utils.getIntegerFromVarName("r", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.fromInt(u8, 2), q);
    try std.testing.expectEqual(Felt252.fromInt(u8, 1), r);
}

test "MathHints: unsigned div rem out of range" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "div",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-7)),
            },
        },
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 15)),
            },
        },
        .{
            .name = "r",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "q",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.UNSIGNED_DIV_REM, ids_data, .{});

    try std.testing.expectError(
        HintError.OutOfValidRange,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: unsigned div rem  incorrect ids" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "diiiv",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-7)),
            },
        },
        .{
            .name = "vvvalue",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 15)),
            },
        },
        .{
            .name = "a",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "b",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.UNSIGNED_DIV_REM, ids_data, .{});

    try std.testing.expectError(
        HintError.UnknownIdentifier,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: assertLeFelt valid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    try exec_scopes.assignOrUpdateVariable("exclued", .{ .u64 = 1 });

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("starkware.cairo.common.math.assert_le_felt.PRIME_OVER_3_HIGH", Felt252.fromInt(u256, 0x4000000000000088000000000000001));
    try constants.put("starkware.cairo.common.math.assert_le_felt.PRIME_OVER_2_HIGH", Felt252.fromInt(u256, 0x2AAAAAAAAAAAAB05555555555555556));

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 1)),
            },
        },
        .{
            .name = "b",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 2)),
            },
        },
        .{
            .name = "range_check_ptr",
            .elems = &.{
                MaybeRelocatable.fromRelocatable(Relocatable.init(2, 0)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_LE_FELT,
        ids_data,
        .{},
    );

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, &exec_scopes);
}

test "MathHints: assertLeFelt invalid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    try exec_scopes.assignOrUpdateVariable("exclued", .{
        .felt = Felt252.one(),
    });

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("starkware.cairo.common.math.assert_le_felt.PRIME_OVER_3_HIGH", Felt252.fromInt(u256, 0x4000000000000088000000000000001));
    try constants.put("starkware.cairo.common.math.assert_le_felt.PRIME_OVER_2_HIGH", Felt252.fromInt(u256, 0x2AAAAAAAAAAAAB05555555555555556));

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 2)),
            },
        },
        .{
            .name = "b",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 1)),
            },
        },
        .{
            .name = "range_check_ptr",
            .elems = &.{
                MaybeRelocatable.fromRelocatable(Relocatable.init(1, 0)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_LE_FELT,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        HintError.NonLeFelt252,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, &exec_scopes),
    );
}

test "MathHints: assertLtFelt valid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 1)),
            },
        },
        .{
            .name = "b",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 2)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_LT_FELT,
        ids_data,
        .{},
    );

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
}

test "MathHints: assertLtFelt invalid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "a",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 3)),
            },
        },
        .{
            .name = "b",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 2)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(
        hint_codes.ASSERT_LT_FELT,
        ids_data,
        .{},
    );

    try std.testing.expectError(
        HintError.AssertLtFelt252,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "MathHints: assert 250 bit valid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("UPPER_BOUND", Felt252.fromInt(u64, 10));
    try constants.put("SHIFT", Felt252.fromInt(u64, 1));

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 3)),
            },
        },
        .{
            .name = "high",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "low",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.ASSERT_250_BITS, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, undefined);

    try std.testing.expectEqual(Felt252.fromInt(u8, 3), try hint_utils.getIntegerFromVarName("high", &vm, ids_data, .{}));
    try std.testing.expectEqual(Felt252.fromInt(u8, 0), try hint_utils.getIntegerFromVarName("low", &vm, ids_data, .{}));
}

test "MathHints: assert 250 bit invalid" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("UPPER_BOUND", Felt252.fromInt(u64, 10));
    try constants.put("SHIFT", Felt252.fromInt(u64, 1));

    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 20)),
            },
        },
        .{
            .name = "high",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "low",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.ASSERT_250_BITS, ids_data, .{});

    try std.testing.expectError(HintError.ValueOutside250BitRange, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, undefined));
}

test "MathHints: SplitFelt success" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("MAX_HIGH", Felt252.fromInt(u256, 10633823966279327296825105735305134080));
    try constants.put("MAX_LOW", Felt252.fromInt(u64, 0));

    const firstLimb = Felt252.fromInt(u8, 1);
    const secondLimb = Felt252.fromInt(u8, 2);
    const thirdLimb = Felt252.fromInt(u8, 3);
    const fourthLimb = Felt252.fromInt(u8, 4);
    const value = fourthLimb.bitOr(thirdLimb.shl(64).bitOr(secondLimb.shl(128).bitOr(firstLimb.shl(192))));

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(value),
            },
        },
        .{
            .name = "high",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "low",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_FELT, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, undefined);

    const high = try hint_utils.getIntegerFromVarName("high", &vm, ids_data, .{});
    const low = try hint_utils.getIntegerFromVarName("low", &vm, ids_data, .{});

    if (!high.equal(firstLimb.shl(64).bitOr(secondLimb)))
        return error.HighValueWrong;

    if (!low.equal(thirdLimb.shl(64).bitOr(fourthLimb)))
        return error.LowValueWrong;
}

test "MathHints: SplitFelt unsuccess" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("MAX_HIGH", Felt252.fromInt(u256, 0xffffffffffffffffffffffffffffffff));
    try constants.put("MAX_LOW", Felt252.fromInt(u256, 0xffffffffffffffffffffffffffffffff));

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 1)),
            },
        },
        .{
            .name = "high",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "low",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_FELT, ids_data, .{});

    try std.testing.expectError(HintError.AssertionFailed, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, undefined));
}

test "MathHints: SplitFelt unsuccess low failed" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("MAX_HIGH", Felt252.fromInt(u256, 0xfffffffffffffffffffffffffff));
    try constants.put("MAX_LOW", Felt252.fromInt(u256, 0xffffffffffffffffffffffffffffffff));

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 1)),
            },
        },
        .{
            .name = "high",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "low",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_FELT, ids_data, .{});

    try std.testing.expectError(HintError.AssertionFailed, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, undefined));
}

test "MathHints: SplitFelt unsuccess high failed" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("MAX_HIGH", Felt252.fromInt(u256, 0xfffffffffffffffffffffffffffffff));
    try constants.put("MAX_LOW", Felt252.fromInt(u256, 0xfffffffffffffffffffffffffff));

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 1)),
            },
        },
        .{
            .name = "high",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "low",
            .elems = &.{
                null,
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_FELT, ids_data, .{});

    try std.testing.expectError(HintError.AssertionFailed, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, undefined));
}

test "MathHints: splitIntAssertRange success" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.zero()),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_INT_ASSERT_RANGE, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
}

test "MathHints: splitIntAssertRange failed" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    _ = try vm.addMemorySegment();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 3)),
            },
        },
    }, &vm);
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_INT_ASSERT_RANGE, ids_data, .{});

    try std.testing.expectError(HintError.SplitIntNotZero, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}

test "MathHints: signed div rem success" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "div",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 3)),
            },
        },
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 10)),
            },
        },
        .{
            .name = "bound",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 29)),
            },
        },
        .{
            .name = "r",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "biased_q",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SIGNED_DIV_REM, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const biased_q = try hint_utils.getIntegerFromVarName("biased_q", &vm, ids_data, .{});
    const r = try hint_utils.getIntegerFromVarName("r", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.fromInt(u8, 32), biased_q);
    try std.testing.expectEqual(Felt252.fromInt(u8, 1), r);
}

test "MathHints: signed div rem success with negative" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "div",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 7)),
            },
        },
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-10)),
            },
        },
        .{
            .name = "bound",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 29)),
            },
        },
        .{
            .name = "r",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "biased_q",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SIGNED_DIV_REM, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const biased_q = try hint_utils.getIntegerFromVarName("biased_q", &vm, ids_data, .{});
    const r = try hint_utils.getIntegerFromVarName("r", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.fromInt(u8, 27), biased_q);
    try std.testing.expectEqual(Felt252.fromInt(u8, 4), r);
}

test "MathHints: signed div rem div zero error" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "div",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 0)),
            },
        },
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-10)),
            },
        },
        .{
            .name = "bound",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 29)),
            },
        },
        .{
            .name = "r",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "biased_q",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SIGNED_DIV_REM, ids_data, .{});

    try std.testing.expectError(HintError.OutOfValidRange, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}

test "MathHints: signed div rem div error out of range" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "div",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 4)),
            },
        },
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(16)),
            },
        },
        .{
            .name = "bound",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 2)),
            },
        },
        .{
            .name = "r",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "biased_q",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SIGNED_DIV_REM, ids_data, .{});

    try std.testing.expectError(HintError.OutOfValidRange, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}

test "MathHints: signed div rem div error out of rc bound" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });
    _ = try vm.addMemorySegment();

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "div",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 10633823966279327296825105735305134081)),
            },
        },
        .{
            .name = "value",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(16)),
            },
        },
        .{
            .name = "bound",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u32, 2)),
            },
        },
        .{
            .name = "r",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "biased_q",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SIGNED_DIV_REM, ids_data, .{});

    try std.testing.expectError(HintError.OutOfValidRange, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}
