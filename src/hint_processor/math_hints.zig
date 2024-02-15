const std = @import("std");

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;
const CoreVM = @import("../vm/core.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
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
        if (signed_value.abs > bound.toInteger()) {
            return HintError.ValueOutsideValidRange;
        }
    }

    try hint_utils.insertValueFromVarName(allocator, "is_positive", MaybeRelocatable.fromFelt(
        if (signed_value.positive) Felt252.one() else Felt252.zero(),
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

    const builtin_runner = try vm.getBuiltinRunner(.Signature);

    try builtin_runner.Signature.addSignature(ecdsa_ptr, .{
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
// pub fn isQuadResidue(allcator: Allocator, ids: IdsManager, vm: *VirtualMachine) !void {
// 	const x = try ids.getFelt("x", vm);
//     if (x.isZero() or x.isOne()) {
//         try ids.insert(allocator, "y", MaybeRelocatable.fromFelt(x), vm);
//     } else if (x.pow(SIGNED_FELT_MAX).equal(Felt252.one())) {
//         try ids.insert(allocator, "y", MaybeRelocatable.fromFelt(x.sqrt().?), vm);
//     } else {
//         try ids.insert(allocator, "y", MaybeRelocatable.fromFelt(try x.div(Felt252.fromInt(u8, 3))), vm);

//     }
// 	f x.IsZero() || x.IsOne() {
// 		ids.Insert("y", NewMaybeRelocatableFelt(x), vm)

// 	} else if x.Pow(SignedFeltMaxValue()) == FeltOne() {
// 		num := x.Sqrt()
// 		ids.Insert("y", NewMaybeRelocatableFelt(num), vm)

// 	} else {
// 		num := (x.Div(lambdaworks.FeltFromUint64(3))).Sqrt()
// 		ids.Insert("y", NewMaybeRelocatableFelt(num), vm)
// 	}
// 	return nil
// }

// importing testing utils for tests
const testing_utils = @import("testing_utils.zig");

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
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(i32, -1)),
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
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(i32, -1)),
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
