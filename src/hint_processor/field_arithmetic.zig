const std = @import("std");
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintData = @import("hint_processor_def.zig").HintData;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;

const BigInt3 = @import("builtin_hint_processor/secp/bigint_utils.zig").BigInt3;
const Uint384 = @import("builtin_hint_processor/secp/bigint_utils.zig").Uint384;
const BigInt5 = @import("builtin_hint_processor/secp/bigint_utils.zig").BigInt5;
const BigIntN = @import("builtin_hint_processor/secp/bigint_utils.zig").BigIntN;

const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

const Int = @import("std").math.big.int.Managed;
const BASE = @import("../math/fields/constants.zig").BASE;

const hint_codes = @import("builtin_hint_codes.zig");
const hint_utils = @import("hint_utils.zig");
const testing_utils = @import("testing_utils.zig");
const field_helper = @import("../math/fields/helper.zig");
const safeDivBigInt = @import("../math/fields/helper.zig").safeDivBigInt;

//  Implements Hint:
// %{
//     from starkware.python.math_utils import is_quad_residue, sqrt

//     def split(num: int, num_bits_shift: int = 128, length: int = 3):
//         a = []
//         for _ in range(length):
//             a.append( num & ((1 << num_bits_shift) - 1) )
//             num = num >> num_bits_shift
//         return tuple(a)

//     def pack(z, num_bits_shift: int = 128) -> int:
//         limbs = (z.d0, z.d1, z.d2)
//         return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//     generator = pack(ids.generator)
//     x = pack(ids.x)
//     p = pack(ids.p)

//     success_x = is_quad_residue(x, p)
//     root_x = sqrt(x, p) if success_x else None

//     success_gx = is_quad_residue(generator*x, p)
//     root_gx = sqrt(generator*x, p) if success_gx else None

//     # Check that one is 0 and the other is 1
//     if x != 0:
//         assert success_x + success_gx ==1

//     # `None` means that no root was found, but we need to transform these into a felt no matter what
//     if root_x == None:
//         root_x = 0
//     if root_gx == None:
//         root_gx = 0
//     ids.success_x = int(success_x)
//     ids.success_gx = int(success_gx)
//     split_root_x = split(root_x)
//     split_root_gx = split(root_gx)
//     ids.sqrt_x.d0 = split_root_x[0]
//     ids.sqrt_x.d1 = split_root_x[1]
//     ids.sqrt_x.d2 = split_root_x[2]
//     ids.sqrt_gx.d0 = split_root_gx[0]
//     ids.sqrt_gx.d1 = split_root_gx[1]
//     ids.sqrt_gx.d2 = split_root_gx[2]
// %}
pub fn u384GetSquareRoot(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    try bigIntIntGetSquareRoot(allocator, vm, ids_data, ap_tracking, 3);
}

// Implements Hint:
// %{
//     from starkware.python.math_utils import is_quad_residue, sqrt

//     def split(a: int):
//         return (a & ((1 << 128) - 1), a >> 128)

//     def pack(z) -> int:
//         return z.low + (z.high << 128)

//     generator = pack(ids.generator)
//     x = pack(ids.x)
//     p = pack(ids.p)

//     success_x = is_quad_residue(x, p)
//     root_x = sqrt(x, p) if success_x else None
//     success_gx = is_quad_residue(generator*x, p)
//     root_gx = sqrt(generator*x, p) if success_gx else None

//     # Check that one is 0 and the other is 1
//     if x != 0:
//         assert success_x + success_gx == 1

//     # `None` means that no root was found, but we need to transform these into a felt no matter what
//     if root_x == None:
//         root_x = 0
//     if root_gx == None:
//         root_gx = 0
//     ids.success_x = int(success_x)
//     ids.success_gx = int(success_gx)
//     split_root_x = split(root_x)
//     # print('split root x', split_root_x)
//     split_root_gx = split(root_gx)
//     ids.sqrt_x.low = split_root_x[0]
//     ids.sqrt_x.high = split_root_x[1]
//     ids.sqrt_gx.low = split_root_gx[0]
//     ids.sqrt_gx.high = split_root_gx[1]
// %}
pub fn u256GetSquareRoot(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    try bigIntIntGetSquareRoot(allocator, vm, ids_data, ap_tracking, 2);
}

pub fn bigIntIntGetSquareRoot(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    comptime NUM_LIMBS: usize,
) !void {
    var generator = try (try BigIntN(NUM_LIMBS).fromVarName("generator", vm, ids_data, ap_tracking)).pack(allocator);
    defer generator.deinit();

    var x = try (try BigIntN(NUM_LIMBS).fromVarName("x", vm, ids_data, ap_tracking)).pack(allocator);
    defer x.deinit();
    var p = try (try BigIntN(NUM_LIMBS).fromVarName("p", vm, ids_data, ap_tracking)).pack(allocator);
    defer p.deinit();

    const success_x = try field_helper.isQuadResidue(allocator, x, p);

    var root_x = if (success_x)
        (try field_helper.sqrtPrimePower(allocator, x, p)) orelse try Int.initSet(allocator, 0)
    else
        try Int.initSet(allocator, 0);
    defer root_x.deinit();

    var gx = try Int.init(allocator);
    defer gx.deinit();

    try gx.mul(&generator, &x);

    const success_gx = try field_helper.isQuadResidue(allocator, gx, p);

    var root_gx = if (success_gx)
        (try field_helper.sqrtPrimePower(allocator, gx, p)) orelse try Int.initSet(allocator, 0)
    else
        try Int.initSet(allocator, 0);
    defer root_gx.deinit();

    if (!x.eqlZero() and (@intFromBool(success_x) ^ @intFromBool(success_gx)) == 0)
        return HintError.AssertionFailed;

    try hint_utils.insertValueFromVarName(
        allocator,
        "success_x",
        MaybeRelocatable.fromInt(u8, if (success_x) 1 else 0),
        vm,
        ids_data,
        ap_tracking,
    );
    try hint_utils.insertValueFromVarName(
        allocator,
        "success_gx",
        MaybeRelocatable.fromInt(u8, if (success_gx) 1 else 0),
        vm,
        ids_data,
        ap_tracking,
    );

    try (try BigIntN(NUM_LIMBS).split(allocator, root_x)).insertFromVarName(allocator, "sqrt_x", vm, ids_data, ap_tracking);
    try (try BigIntN(NUM_LIMBS).split(allocator, root_gx)).insertFromVarName(allocator, "sqrt_gx", vm, ids_data, ap_tracking);
}

// Implements Hint:
//  %{
//     from starkware.python.math_utils import div_mod

//     def split(num: int, num_bits_shift: int, length: int):
//         a = []
//         for _ in range(length):
//             a.append( num & ((1 << num_bits_shift) - 1) )
//             num = num >> num_bits_shift
//         return tuple(a)

//     def pack(z, num_bits_shift: int) -> int:
//         limbs = (z.d0, z.d1, z.d2)
//         return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//     a = pack(ids.a, num_bits_shift = 128)
//     b = pack(ids.b, num_bits_shift = 128)
//     p = pack(ids.p, num_bits_shift = 128)
//     # For python3.8 and above the modular inverse can be computed as follows:
//     # b_inverse_mod_p = pow(b, -1, p)
//     # Instead we use the python3.7-friendly function div_mod from starkware.python.math_utils
//     b_inverse_mod_p = div_mod(1, b, p)

//     b_inverse_mod_p_split = split(b_inverse_mod_p, num_bits_shift=128, length=3)

//     ids.b_inverse_mod_p.d0 = b_inverse_mod_p_split[0]
//     ids.b_inverse_mod_p.d1 = b_inverse_mod_p_split[1]
//     ids.b_inverse_mod_p.d2 = b_inverse_mod_p_split[2]
// %}
pub fn uint384Div(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Note: ids.a is not used here, nor is it used by following hints, so we dont need to extract it.
    var b = try (try Uint384.fromVarName("b", vm, ids_data, ap_tracking)).pack(allocator);
    defer b.deinit();
    var p = try (try Uint384.fromVarName("p", vm, ids_data, ap_tracking)).pack(allocator);
    defer p.deinit();

    if (b.eqlZero())
        return MathError.DividedByZero;

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var b_inverse_mod_p = try field_helper.mulInv(allocator, b, p);
    defer b_inverse_mod_p.deinit();

    try tmp.divFloor(&b_inverse_mod_p, &b_inverse_mod_p, &p);

    b_inverse_mod_p.abs();

    const b_inverse_mod_p_split = try Uint384.split(allocator, b_inverse_mod_p);
    try b_inverse_mod_p_split.insertFromVarName(allocator, "b_inverse_mod_p", vm, ids_data, ap_tracking);
}

test "FieldArithmetic: run u384 getSquareOk goldilocks prime" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 14;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "p", -14 },
        .{ "x", -11 },
        .{ "generator", -8 },
        .{ "sqrt_x", -5 },
        .{ "sqrt_gx", -2 },
        .{ "success_x", 1 },
        .{ "success_gx", 2 },
    });
    defer ids_data.deinit();
    //Insert ids into memory

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        // p
        .{ .{ 1, 0 }, .{18446744069414584321} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },

        //x
        .{ .{ 1, 3 }, .{25} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },

        //generator
        .{ .{ 1, 6 }, .{7} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_GET_SQUARE_ROOT, undefined, undefined);
    //Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        // sqrt_x
        .{ .{ 1, 9 }, .{5} },
        .{ .{ 1, 10 }, .{0} },
        .{ .{ 1, 11 }, .{0} },
        // sqrt_gx
        .{ .{ 1, 12 }, .{0} },
        .{ .{ 1, 13 }, .{0} },
        .{ .{ 1, 14 }, .{0} },
        // success_x
        .{ .{ 1, 15 }, .{1} },
        // success_gx
        .{ .{ 1, 16 }, .{0} },
    });
}

test "FieldArithmetic: run u384 getSquareOk success gx" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 14;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "p", -14 },
        .{ "x", -11 },
        .{ "generator", -8 },
        .{ "sqrt_x", -5 },
        .{ "sqrt_gx", -2 },
        .{ "success_x", 1 },
        .{ "success_gx", 2 },
    });
    defer ids_data.deinit();
    //Insert ids into memory

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        // p
        .{ .{ 1, 0 }, .{3} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },

        //x
        .{ .{ 1, 3 }, .{17} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },

        //generator
        .{ .{ 1, 6 }, .{71} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_GET_SQUARE_ROOT, undefined, undefined);
    //Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        // sqrt_x
        .{ .{ 1, 9 }, .{0} },
        .{ .{ 1, 10 }, .{0} },
        .{ .{ 1, 11 }, .{0} },
        // sqrt_gx
        .{ .{ 1, 12 }, .{1} },
        .{ .{ 1, 13 }, .{0} },
        .{ .{ 1, 14 }, .{0} },
        // success_x
        .{ .{ 1, 15 }, .{0} },
        // success_gx
        .{ .{ 1, 16 }, .{1} },
    });
}

test "FieldArithmetic: run u384 getSquareOk no successes" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 14;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "p", -14 },
        .{ "x", -11 },
        .{ "generator", -8 },
        .{ "sqrt_x", -5 },
        .{ "sqrt_gx", -2 },
        .{ "success_x", 1 },
        .{ "success_gx", 2 },
    });
    defer ids_data.deinit();
    //Insert ids into memory

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        // p
        .{ .{ 1, 0 }, .{3} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },

        //x
        .{ .{ 1, 3 }, .{17} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },

        //generator
        .{ .{ 1, 6 }, .{1} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    //Execute the hint
    try std.testing.expectError(
        HintError.AssertionFailed,
        testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            hint_codes.UINT384_GET_SQUARE_ROOT,
            undefined,
            undefined,
        ),
    );
}

test "FieldArithmetic: run u384 div ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 11;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -11 },
        .{ "b", -8 },
        .{ "p", -5 },
        .{ "b_inverse_mod_p", -2 },
    });
    defer ids_data.deinit();
    //Insert ids into memory

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        // a
        .{ .{ 1, 0 }, .{25} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },

        //b
        .{ .{ 1, 3 }, .{5} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },

        //p
        .{ .{ 1, 6 }, .{31} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.UINT384_DIV,
        undefined,
        undefined,
    );
    //Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        // b_inverse_mod_p
        .{ .{ 1, 9 }, .{25} },
        .{ .{ 1, 10 }, .{0} },
        .{ .{ 1, 11 }, .{0} },
    });
}

test "FieldArithmetic: run u384 div b is zero" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 11;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -11 },
        .{ "b", -8 },
        .{ "p", -5 },
        .{ "b_inverse_mod_p", -2 },
    });
    defer ids_data.deinit();
    //Insert ids into memory

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        // a
        .{ .{ 1, 0 }, .{25} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },

        //b
        .{ .{ 1, 3 }, .{0} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },

        //p
        .{ .{ 1, 6 }, .{31} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    //Execute the hint
    try std.testing.expectError(MathError.DividedByZero, testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.UINT384_DIV,
        undefined,
        undefined,
    ));
}
