const std = @import("std");

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

fn isqrt(n: u256) !u256 {
    var x = n;
    var y = (n + 1) >> @as(u32, 1);

    while (y < x) {
        x = y;
        y = (@divFloor(n, x) + x) >> @as(u32, 1);
    }

    if (!(std.math.pow(u256, x, 2) <= n and n < std.math.pow(u256, x + 1, 2))) {
        return error.FailedToGetSqrt;
    }

    return x;
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

    const root = Felt252.fromInt(u256, isqrt(mod_value.toInteger()) catch unreachable);

    try hint_utils.insertValueFromVarName(
        allocator,
        "root",
        MaybeRelocatable.fromFelt(root),
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
                MaybeRelocatable.fromRelocatable(Relocatable.init(0, 0)),
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
                MaybeRelocatable.fromFelt(Felt252.fromSignedInt(i32, -81)),
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
