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

const Uint384 = bigint_utils.Uint384;
const Uint768 = bigint_utils.Uint768;
const Int = @import("std").math.big.int.Managed;

// Implements Hint:
// %{
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
//     div = pack(ids.div, num_bits_shift = 128)
//     quotient, remainder = divmod(a, div)

//     quotient_split = split(quotient, num_bits_shift=128, length=3)
//     assert len(quotient_split) == 3

//     ids.quotient.d0 = quotient_split[0]
//     ids.quotient.d1 = quotient_split[1]
//     ids.quotient.d2 = quotient_split[2]

//     remainder_split = split(remainder, num_bits_shift=128, length=3)
//     ids.remainder.d0 = remainder_split[0]
//     ids.remainder.d1 = remainder_split[1]
//     ids.remainder.d2 = remainder_split[2]
// %}
pub fn uint384UnsignedDivRem(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var a = try (try Uint384.fromVarName("a", vm, ids_data, ap_tracking)).pack(allocator);
    defer a.deinit();
    var div = try (try Uint384.fromVarName("div", vm, ids_data, ap_tracking)).pack(allocator);
    defer div.deinit();

    if (div.eqlZero()) {
        return MathError.DividedByZero;
    }

    var quotient = try Int.init(allocator);
    defer quotient.deinit();
    var remainder = try Int.init(allocator);
    defer remainder.deinit();

    try quotient.divFloor(&remainder, &a, &div);

    const quotient_split = try Uint384.split(allocator, quotient);
    try quotient_split.insertFromVarName(allocator, "quotient", vm, ids_data, ap_tracking);

    const remainder_split = try Uint384.split(allocator, remainder);
    try remainder_split.insertFromVarName(allocator, "remainder", vm, ids_data, ap_tracking);
}

// Implements Hint:
//    %{
//        ids.low = ids.a & ((1<<128) - 1)
//        ids.high = ids.a >> 128
//    %}
pub fn uint384Split128(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const bound = Felt252.pow2Const(128);
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);

    const high, const low = try a.divRem(bound);

    try hint_utils.insertValueFromVarName(allocator, "low", MaybeRelocatable.fromFelt(low), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "high", MaybeRelocatable.fromFelt(high), vm, ids_data, ap_tracking);
}

// Implements Hint:
// %{
//     sum_d0 = ids.a.d0 + ids.b.d0
//     ids.carry_d0 = 1 if sum_d0 >= ids.SHIFT else 0
//     sum_d1 = ids.a.d1 + ids.b.d1 + ids.carry_d0
//     ids.carry_d1 = 1 if sum_d1 >= ids.SHIFT else 0
//     sum_d2 = ids.a.d2 + ids.b.d2 + ids.carry_d1
//     ids.carry_d2 = 1 if sum_d2 >= ids.SHIFT else 0
// %}
pub fn addNoUint384Check(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const a = try Uint384.fromVarName("a", vm, ids_data, ap_tracking);
    const b = try Uint384.fromVarName("b", vm, ids_data, ap_tracking);
    // This hint is not from the cairo commonlib, and its lib can be found under different paths, so we cant rely on a full path name
    var shift = try (try hint_utils.getConstantFromVarName("SHIFT", constants)).toStdBigSignedInt(allocator);
    defer shift.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();
    var tmp2 = try Int.init(allocator);
    defer tmp2.deinit();
    var tmp3 = try Int.init(allocator);
    defer tmp3.deinit();

    var buffer: [20]u8 = undefined;

    inline for (0..3) |i| {
        try tmp.set(try a.limbs[i].toSignedInt(i256));
        try tmp2.set(try b.limbs[i].toSignedInt(i256));

        try tmp3.add(&tmp, &tmp2);

        const result = if (tmp3.order(shift) == .gt or tmp3.order(shift) == .eq)
            Felt252.one()
        else
            Felt252.zero();

        try hint_utils.insertValueFromVarName(
            allocator,
            try std.fmt.bufPrint(buffer[0..], "carry_d{d}", .{i}),
            MaybeRelocatable.fromFelt(result),
            vm,
            ids_data,
            ap_tracking,
        );
    }
}

//  Implements Hint
// %{
//     from starkware.python.math_utils import isqrt

//     def split(num: int, num_bits_shift: int, length: int):
//         a = []
//         for _ in range(length):
//             a.append( num & ((1 << num_bits_shift) - 1) )
//             num = num >> num_bits_shift
//         return tuple(a)

//     def pack(z, num_bits_shift: int) -> int:
//         limbs = (z.d0, z.d1, z.d2)
//         return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//     a = pack(ids.a, num_bits_shift=128)
//     root = isqrt(a)
//     assert 0 <= root < 2 ** 192
//     root_split = split(root, num_bits_shift=128, length=3)
//     ids.root.d0 = root_split[0]
//     ids.root.d1 = root_split[1]
//     ids.root.d2 = root_split[2]
// %}
pub fn uint384Sqrt(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var a = try (try Uint384.fromVarName("a", vm, ids_data, ap_tracking)).pack(allocator);
    defer a.deinit();

    try a.sqrt(&a);

    if (a.eqlZero() or a.bitCountAbs() > 192) {
        return HintError.AssertionFailed;
    }

    const root_split = try Uint384.split(allocator, a);

    try root_split.insertFromVarName(allocator, "root", vm, ids_data, ap_tracking);
}

// Implements Hint:
// memory[ap] = 1 if 0 <= (ids.a.d2 % PRIME) < 2 ** 127 else 0
pub fn uint384SignedNn(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a_addr = try hint_utils.getRelocatableFromVarName("a", vm, ids_data, ap_tracking);

    const a_d2 = vm.getFelt(try a_addr.addUint(2)) catch return HintError.IdentifierHasNoMember;

    try hint_utils.insertValueIntoAp(allocator, vm, if (a_d2.numBitsLe() <= 127) MaybeRelocatable.fromInt(u8, 1) else MaybeRelocatable.fromInt(u8, 0));
}

//  Implements Hint:
// %{
//     def split(num: int, num_bits_shift: int, length: int):
//         a = []
//         for _ in range(length):
//         a.append( num & ((1 << num_bits_shift) - 1) )
//         num = num >> num_bits_shift
//         return tuple(a)

//     def pack(z, num_bits_shift: int) -> int:
//         limbs = (z.d0, z.d1, z.d2)
//         return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//     a = pack(ids.a, num_bits_shift = 128)
//     b = pack(ids.b, num_bits_shift = 128)
//     p = pack(ids.p, num_bits_shift = 128)

//     res = (a - b) % p

//     res_split = split(res, num_bits_shift=128, length=3)

//     ids.res.d0 = res_split[0]
//     ids.res.d1 = res_split[1]
//     ids.res.d2 = res_split[2]
// %}
pub fn subReducedAAndReducedB(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var a = try (try Uint384.fromVarName("a", vm, ids_data, ap_tracking)).pack(allocator);
    defer a.deinit();
    var b = try (try Uint384.fromVarName("b", vm, ids_data, ap_tracking)).pack(allocator);
    defer b.deinit();
    var p = try (try Uint384.fromVarName("p", vm, ids_data, ap_tracking)).pack(allocator);
    defer p.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();
    var tmp2 = try Int.init(allocator);
    defer tmp2.deinit();

    if (a.order(b) == .gt) {
        try tmp.sub(&a, &b);
        try tmp2.divFloor(&tmp, &tmp, &p);
    } else {
        try tmp.sub(&b, &a);
        try tmp.sub(&p, &tmp);
        try tmp2.divFloor(&tmp, &tmp, &p);
    }

    const res_split = try Uint384.split(allocator, tmp);

    try res_split.insertFromVarName(allocator, "res", vm, ids_data, ap_tracking);
}

// Implements Hint:
//       %{
//           def split(num: int, num_bits_shift: int, length: int):
//               a = []
//               for _ in range(length):
//                   a.append( num & ((1 << num_bits_shift) - 1) )
//                   num = num >> num_bits_shift
//               return tuple(a)

//           def pack(z, num_bits_shift: int) -> int:
//               limbs = (z.d0, z.d1, z.d2)
//               return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//           def pack_extended(z, num_bits_shift: int) -> int:
//               limbs = (z.d0, z.d1, z.d2, z.d3, z.d4, z.d5)
//               return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//           a = pack_extended(ids.a, num_bits_shift = 128)
//           div = pack(ids.div, num_bits_shift = 128)

//           quotient, remainder = divmod(a, div)

//           quotient_split = split(quotient, num_bits_shift=128, length=6)

//           ids.quotient.d0 = quotient_split[0]
//           ids.quotient.d1 = quotient_split[1]
//           ids.quotient.d2 = quotient_split[2]
//           ids.quotient.d3 = quotient_split[3]
//           ids.quotient.d4 = quotient_split[4]
//           ids.quotient.d5 = quotient_split[5]

//           remainder_split = split(remainder, num_bits_shift=128, length=3)
//           ids.remainder.d0 = remainder_split[0]
//           ids.remainder.d1 = remainder_split[1]
//           ids.remainder.d2 = remainder_split[2]
//       %}
pub fn unsignedDivRemUint768ByUint384(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var a = try (try Uint768.fromVarName("a", vm, ids_data, ap_tracking)).pack(allocator);
    defer a.deinit();

    var div = try (try Uint384.fromVarName("div", vm, ids_data, ap_tracking)).pack(allocator);
    defer div.deinit();

    if (div.eqlZero()) {
        return MathError.DividedByZero;
    }

    var quotient = try Int.init(allocator);
    defer quotient.deinit();
    var remainder = try Int.init(allocator);
    defer remainder.deinit();

    try quotient.divFloor(&remainder, &a, &div);

    const quotient_split = try Uint768.split(allocator, quotient);
    try quotient_split.insertFromVarName(allocator, "quotient", vm, ids_data, ap_tracking);

    const remainder_split = try Uint384.split(allocator, remainder);
    try remainder_split.insertFromVarName(allocator, "remainder", vm, ids_data, ap_tracking);
}

test "Uint384: runUnsignedDivRemOk" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 10;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -9 }, .{ "div", -6 }, .{ "quotient", -3 }, .{ "remainder", 0 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{83434123481193248} },
        .{ .{ 1, 2 }, .{82349321849739284} },
        .{ .{ 1, 3 }, .{839243219401320423} },
        .{ .{ 1, 4 }, .{9283430921839492319493} },
        .{ .{ 1, 5 }, .{313248123482483248} },
        .{ .{ 1, 6 }, .{3790328402913840} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_UNSIGNED_DIV_REM, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 7 }, .{221} },
        .{ .{ 1, 8 }, .{0} },
        .{ .{ 1, 9 }, .{0} },
        .{ .{ 1, 10 }, .{340282366920936411825224315027446796751} },
        .{ .{ 1, 11 }, .{340282366920938463394229121463989152931} },
        .{ .{ 1, 12 }, .{1580642357361782} },
    });
}

test "Uint384: runUnsignedDivRem divide by zero" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 10;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -9 }, .{ "div", -6 }, .{ "quotient", -3 }, .{ "remainder", 0 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{83434123481193248} },
        .{ .{ 1, 2 }, .{82349321849739284} },
        .{ .{ 1, 3 }, .{839243219401320423} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{0} },
        .{ .{ 1, 6 }, .{0} },
    });

    try std.testing.expectError(
        MathError.DividedByZero,
        testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            hint_codes.UINT384_UNSIGNED_DIV_REM,
            undefined,
            undefined,
        ),
    );
}

test "Uint384: runSplit128 ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "a", "low", "high",
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{34895349583295832495320945304} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_SPLIT_128, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 1 }, .{34895349583295832495320945304} },
        .{ .{ 1, 2 }, .{0} },
    });
}

test "Uint384: runSplit128 ok big number" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "a", "low", "high",
    });
    defer ids_data.deinit();

    inline for (0..2) |_| _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{std.math.maxInt(u128) * 20} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_SPLIT_128, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 1 }, .{340282366920938463463374607431768211436} },
        .{ .{ 1, 2 }, .{19} },
    });
}

test "Uint384: run addNoCheck ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 10;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -10 },       .{ "b", -7 },        .{ "carry_d0", -4 },
        .{ "carry_d1", -3 }, .{ "carry_d2", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{3789423292314891293} },
        .{ .{ 1, 1 }, .{21894} },
        .{ .{ 1, 2 }, .{340282366920938463463374607431768211455} },
        .{ .{ 1, 3 }, .{32838232} },
        .{ .{ 1, 4 }, .{17} },
        .{ .{ 1, 5 }, .{8} },
    });
    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put("path.path.path.SHIFT", Felt252.pow2Const(128));

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.ADD_NO_UINT384_CHECK, &constants, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 6 }, .{0} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{1} },
    });
}

test "Uint384: sqrt ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 5;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -5 }, .{ "root", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{83434123481193248} },
        .{ .{ 1, 1 }, .{82349321849739284} },
        .{ .{ 1, 2 }, .{839243219401320423} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_SQRT, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{100835122758113432298839930225328621183} },
        .{ .{ 1, 4 }, .{916102188} },
        .{ .{ 1, 5 }, .{0} },
    });
}

test "Uint384: sqrt assertetion failed" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 5;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -5 }, .{ "root", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{-1} },
        .{ .{ 1, 1 }, .{-1} },
        .{ .{ 1, 2 }, .{-1} },
    });

    try std.testing.expectError(
        HintError.AssertionFailed,
        testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            hint_codes.UINT384_SQRT,
            undefined,
            undefined,
        ),
    );
}

test "Uint384: signedNn ok positive" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 3 }, .{1} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_SIGNED_NN, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 0 }, .{1} },
    });
}

test "Uint384: signedNn ok missing identifier" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{1} },
        .{ .{ 1, 2 }, .{1} },
    });

    try std.testing.expectError(
        HintError.IdentifierHasNoMember,
        testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            hint_codes.UINT384_SIGNED_NN,
            undefined,
            undefined,
        ),
    );
}

test "Uint384: signedNn ok negative" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 3 }, .{170141183460469231731687303715884105729} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UINT384_SIGNED_NN, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 0 }, .{0} },
    });
}

test "Uint384: subAsubB ok a max" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 10;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -10 },
        .{ "b", -7 },
        .{ "p", -4 },
        .{ "res", -1 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{6} },
        .{ .{ 1, 1 }, .{6} },
        .{ .{ 1, 2 }, .{6} },
        .{ .{ 1, 3 }, .{1} },
        .{ .{ 1, 4 }, .{1} },
        .{ .{ 1, 5 }, .{1} },
        .{ .{ 1, 6 }, .{7} },
        .{ .{ 1, 7 }, .{7} },
        .{ .{ 1, 8 }, .{7} },
    });

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.SUB_REDUCED_A_AND_REDUCED_B,
        undefined,
        undefined,
    );

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 9 }, .{5} },
        .{ .{ 1, 10 }, .{5} },
        .{ .{ 1, 11 }, .{5} },
    });
}

test "Uint384: subAsubB ok b max" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 10;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -10 },
        .{ "b", -7 },
        .{ "p", -4 },
        .{ "res", -1 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{3} },
        .{ .{ 1, 1 }, .{3} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{5} },
        .{ .{ 1, 4 }, .{5} },
        .{ .{ 1, 5 }, .{5} },
        .{ .{ 1, 6 }, .{7} },
        .{ .{ 1, 7 }, .{7} },
        .{ .{ 1, 8 }, .{7} },
    });

    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_codes.SUB_REDUCED_A_AND_REDUCED_B,
        undefined,
        undefined,
    );

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 9 }, .{5} },
        .{ .{ 1, 10 }, .{5} },
        .{ .{ 1, 11 }, .{5} },
    });
}

test "Uint384: runUnsignedDivRem784 ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 17;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -17 }, .{ "div", -11 }, .{ "quotient", -8 }, .{ "remainder", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{4} },
        .{ .{ 1, 4 }, .{5} },
        .{ .{ 1, 5 }, .{6} },
        .{ .{ 1, 6 }, .{6} },
        .{ .{ 1, 7 }, .{7} },
        .{ .{ 1, 8 }, .{8} },
    });

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.UNSIGNED_DIV_REM_UINT768_BY_UINT384, undefined, undefined);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 9 }, .{328319314958874220607240343889245110272} },
        .{ .{ 1, 10 }, .{329648542954659136480144150949525454847} },
        .{ .{ 1, 11 }, .{255211775190703847597530955573826158591} },
        .{ .{ 1, 12 }, .{0} },
        .{ .{ 1, 13 }, .{0} },
        .{ .{ 1, 14 }, .{0} },
        .{ .{ 1, 15 }, .{71778311772385457136805581255138607105} },
        .{ .{ 1, 16 }, .{147544307532125661892322583691118247938} },
        .{ .{ 1, 17 }, .{3} },
    });
}

test "Uint384: runUnsignedDivRem784 divide by zero" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 17;

    var ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "a", -17 }, .{ "div", -11 }, .{ "quotient", -8 }, .{ "remainder", -2 },
    });
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{4} },
        .{ .{ 1, 4 }, .{5} },
        .{ .{ 1, 5 }, .{6} },
        .{ .{ 1, 6 }, .{0} },
        .{ .{ 1, 7 }, .{0} },
        .{ .{ 1, 8 }, .{0} },
    });

    try std.testing.expectError(
        MathError.DividedByZero,
        testing_utils.runHint(
            std.testing.allocator,
            &vm,
            ids_data,
            hint_codes.UNSIGNED_DIV_REM_UINT768_BY_UINT384,
            undefined,
            undefined,
        ),
    );
}
