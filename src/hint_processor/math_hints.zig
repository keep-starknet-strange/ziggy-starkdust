const std = @import("std");

const CoreVM = @import("../vm/core.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const SIGNED_FELT_MAX = @import("../math/fields/fields.zig").SIGNED_FELT_MAX;
const HintError = @import("../vm/error.zig").HintError;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const CairoVM = CoreVM.CairoVM;
const IdsManager = @import("hint_utils.zig").IdsManager;

// // Implements hint: memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1
// pub fn isNN(
//     ids: IdsManager,
//     vm: *CairoVM,
// ) !void {
//     const a = try ids.getFelt("a", vm);
//     const range_check = try vm.getRangeCheckBuiltin();
//     _ = a;

//     //Main logic (assert a is not negative and within the expected range)
//     const value = if (range_check.bound) |bound| bound else Felt252.zero();
//     // insert_value_into_ap(vm, value)
// }

//Implements hint:
// %{
//     from starkware.cairo.common.math_utils import assert_integer
//     assert_integer(ids.a)
//     assert 0 <= ids.a % PRIME < range_check_builtin.bound, f'a = {ids.a} is out of range.'
// %}
fn assertNN(ids: IdsManager, vm: *CairoVM) !void {
    const a = try ids.getFelt("a", vm);

    const range_check = try vm.getRangeCheckBuiltin();

    if (range_check.bound) |bound| {
        if (a.ge(bound)) {
            return HintError.AssertNNValueOutOfRange;
        }
    }
}

pub fn isPositive(ids: IdsManager, vm: *CairoVM) !void {
    const value = try ids.getFelt("value", vm);
    const range_check = try vm.getRangeCheckBuiltin();

    const signed_value = value.toSignedInt();

    if (range_check.bound) |bound| {
        if (signed_value.abs > bound.toInteger()) {
            return HintError.ValueOutsideValidRange;
        }
    }

    try ids.insert("is_positive", MaybeRelocatable.fromFelt(
        if (signed_value.positive) Felt252.one() else Felt252.zero(),
    ), vm);
}

// Implements hint:from starkware.cairo.common.math.cairo
//
//	%{
//	    from starkware.cairo.common.math_utils import assert_integer
//	    assert_integer(ids.value)
//	    assert ids.value % PRIME != 0, f'assert_not_zero failed: {ids.value} = 0.'
//
// %}

pub fn assertNonZero(ids: IdsManager, vm: *CairoVM) !void {
    const value = try ids.getFelt("value", vm);

    if (value.isZero()) return HintError.AssertNotZero;
}

pub fn verifyEcdsaSignature(ids: IdsManager, vm: *CairoVM) !void {
    const r = try ids.getFelt("signature_r", vm);

    const s = try ids.getFelt("signature_s", vm);

    const ecdsa_ptr = try ids.getAddr("ecdsa_ptr", vm);

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
pub fn isQuadResidue(allcator: Allocator, ids: IdsManager, vm: *VirtualMachine) !void {
	const x = try ids.getFelt("x", vm);
    if (x.isZero() or x.isOne()) {
        try ids.insert(allocator, "y", MaybeRelocatable.fromFelt(x), vm);
    } else if (x.pow(SIGNED_FELT_MAX).equal(Felt252.one())) {
        try ids.insert(allocator, "y", MaybeRelocatable.fromFelt(x.sqrt().?), vm);
    } else {
        try ids.insert(allocator, "y", MaybeRelocatable.fromFelt(try x.div(Felt252.fromInt(u8, 3))), vm);

    }
	f x.IsZero() || x.IsOne() {
		ids.Insert("y", NewMaybeRelocatableFelt(x), vm)

	} else if x.Pow(SignedFeltMaxValue()) == FeltOne() {
		num := x.Sqrt()
		ids.Insert("y", NewMaybeRelocatableFelt(num), vm)

	} else {
		num := (x.Div(lambdaworks.FeltFromUint64(3))).Sqrt()
		ids.Insert("y", NewMaybeRelocatableFelt(num), vm)
	}
	return nil
}

// importing testing utils for tests
const testing_utils = @import("testing_utils.zig");

test "MathHint: isPositive true" {
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    try vm.segments.addSegment();

    var manager = try testing_utils.setupIdsForTest(std.testing.allocator, .{}, vm);

    // try vm.segments.memory.setUpMemory(
    //     std.testing.allocator,
    //     .{
    //         .{ .{ 0, 0 }, .{ 0, 0 } },
    //     },
    // );
    // defer vm.segments.memory.deinitData(std.testing.allocator);

    // IdsManager.init(kj)

}
