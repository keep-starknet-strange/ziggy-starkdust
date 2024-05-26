const std = @import("std");

const testing_utils = @import("testing_utils.zig");
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
const HintType = @import("../vm/types/execution_scopes.zig").HintType;
const Uint256 = @import("uint256_utils.zig").Uint256;

const DictManager = @import("dict_manager.zig").DictManager;
const Rc = @import("../vm/types/execution_scopes.zig").Rc;
const DictTracker = @import("dict_manager.zig").DictTracker;

const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;
const MemoryError = @import("../vm/error.zig").MemoryError;

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

const ADDR_BOUND = "starkware.starknet.common.storage.ADDR_BOUND";

//Implements hint: memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1
pub fn isNn(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const range_check_builtin = try vm.getRangeCheckBuiltin();
    //Main logic (assert a is not negative and within the expected range)
    const value = if (range_check_builtin.bound) |bound| if (a.cmp(&bound).compare(.gte)) Felt252.one() else Felt252.zero() else Felt252.zero();

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(value));
}

//Implements hint: memory[ap] = 0 if 0 <= ((-ids.a - 1) % PRIME) < range_check_builtin.bound else 1
pub fn isNnOutOfRange(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const range_check_builtin = try vm.getRangeCheckBuiltin();
    //Main logic (assert a is not negative and within the expected range)
    //let value = if (-a - 1usize).mod_floor(vm.get_prime()) < range_check_builtin._bound {

    const value = if (range_check_builtin.bound) |bound| if (Felt252.zero().sub(&a.add(&Felt252.one())).cmp(&bound).compare(.lt)) Felt252.zero() else Felt252.one() else Felt252.zero();

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(value));
}

pub fn assertLeFeltV06(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const b = try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking);

    if (a.cmp(&b).compare(.gt)) {
        return HintError.NonLeFelt252;
    }
}

pub fn assertLeFeltV08(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const b = try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking);

    if (a.cmp(&b).compare(.gt)) return HintError.NonLeFelt252;

    const bound = (try vm.getRangeCheckBuiltin()).bound orelse Felt252.zero();
    const small_inputs =
        if (a.cmp(&bound).compare(.lt) and b.sub(&a).cmp(&bound).compare(.lt)) Felt252.one() else Felt252.zero();

    try hint_utils.insertValueFromVarName(allocator, "small_inputs", MaybeRelocatable.fromFelt(small_inputs), vm, ids_data, ap_tracking);
}

// Implements hint:
//   %{
//       ids.a_lsb = ids.a & 1
//       ids.b_lsb = ids.b & 1
//   %}
pub fn abBitand1(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const b = try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking);

    const two = Felt252.two();
    const a_lsb = a.modFloor2(two);
    const b_lsb = b.modFloor2(two);

    try hint_utils.insertValueFromVarName(allocator, "a_lsb", MaybeRelocatable.fromFelt(a_lsb), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "b_lsb", MaybeRelocatable.fromFelt(b_lsb), vm, ids_data, ap_tracking);
}

//Implements hint:from starkware.cairo.common.math_cmp import is_le_felt
//    memory[ap] = 0 if (ids.a % PRIME) <= (ids.b % PRIME) else 1
pub fn isLeFelt(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a_mod = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const b_mod = try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking);

    const value = if (a_mod.cmp(&b_mod).compare(.gt)) Felt252.one() else Felt252.zero();

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(value));
}

//Implements hint: memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base
//        assert res < ids.bound, f'split_int(): Limb {res} is out of range.'
pub fn splitInt(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);
    const base = try hint_utils.getIntegerFromVarName("base", vm, ids_data, ap_tracking);
    const bound = try hint_utils.getIntegerFromVarName("bound", vm, ids_data, ap_tracking);

    if (base.isZero()) return MathError.DividedByZero;

    const output = try hint_utils.getPtrFromVarName("output", vm, ids_data, ap_tracking);

    //Main Logic
    const res = value.modFloor2(base);

    if (res.cmp(&bound).compare(.gt))
        return HintError.SplitIntLimbOutOfRange;

    try vm.insertInMemory(allocator, output, MaybeRelocatable.fromFelt(res));
}

// Implements hint:
// %{
//     # Verify the assumptions on the relationship between 2**250, ADDR_BOUND and PRIME.
//     ADDR_BOUND = ids.ADDR_BOUND % PRIME
//     assert (2**250 < ADDR_BOUND <= 2**251) and (2 * 2**250 < PRIME) and (
//             ADDR_BOUND * 2 > PRIME), \
//         'normalize_address() cannot be used with the current constants.'
//     ids.is_small = 1 if ids.addr < ADDR_BOUND else 0
// %}
pub fn isAddrBounded(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const addr = try hint_utils.getIntegerFromVarName("addr", vm, ids_data, ap_tracking);

    const addr_bound_felt = constants
        .get(ADDR_BOUND) orelse return HintError.MissingConstant;
    const addr_bound = addr_bound_felt.toU256();

    const lower_bound: u256 = 1 << 250;
    const upper_bound: u256 = 1 << 251;

    // assert (2**250 < ADDR_BOUND <= 2**251) and (2 * 2**250 < PRIME) and (
    //      ADDR_BOUND * 2 > PRIME), \
    //      'normalize_address() cannot be used with the current constants.'
    // The second check is not needed, as it's true for the CAIRO_PRIME
    if (!(lower_bound < addr_bound and addr_bound <= upper_bound or (addr_bound << 1) > STARKNET_PRIME))
        return HintError.AssertionFailed;

    // Main logic: ids.is_small = 1 if ids.addr < ADDR_BOUND else 0
    const is_small = if (addr.cmp(&addr_bound_felt).compare(.lt)) Felt252.one() else Felt252.zero();

    try hint_utils.insertValueFromVarName(allocator, "is_small", MaybeRelocatable.fromFelt(is_small), vm, ids_data, ap_tracking);
}

// Implements hint:
// %{ ids.is_250 = 1 if ids.addr < 2**250 else 0 %}
pub fn is250Bits(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const addr = try hint_utils.getIntegerFromVarName("addr", vm, ids_data, ap_tracking);

    // Main logic: ids.is_250 = 1 if ids.addr < 2**250 else 0
    const is_250 = if (addr.numBitsLe() <= 250) Felt252.one() else Felt252.zero();

    try hint_utils.insertValueFromVarName(allocator, "is_250", MaybeRelocatable.fromFelt(is_250), vm, ids_data, ap_tracking);
}

// Implements hint:
//   PRIME = 2**255 - 19
//   II = pow(2, (PRIME - 1) // 4, PRIME)

//   xx = ids.xx.low + (ids.xx.high<<128)
//   x = pow(xx, (PRIME + 3) // 8, PRIME)
//   if (x * x - xx) % PRIME != 0:
//       x = (x * II) % PRIME
//   if x % 2 != 0:
//       x = PRIME - x
//   ids.x.low = x & ((1<<128)-1)
//   ids.x.high = x >> 128
//   Note: doesnt belong to and is not variation of any hint from common/math
pub fn splitXx(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const xx_u = try Uint256.fromVarName("xx", vm, ids_data, ap_tracking);
    const x_addr = try hint_utils.getRelocatableFromVarName("x", vm, ids_data, ap_tracking);

    const xx = xx_u.low.toU256() + xx_u.high.mul(&Felt252.pow2Const(128)).toU256();

    var x = field_helper.powModulus(
        xx,
        @divFloor(SPLIT_XX_PRIME + 3, 8),
        SPLIT_XX_PRIME,
    );

    if (@mod(x * x - xx, SPLIT_XX_PRIME) != 0)
        x = @mod(x * II, SPLIT_XX_PRIME);

    if (@mod(x, 2) != 0)
        x = SPLIT_XX_PRIME - x;

    try vm.insertInMemory(
        allocator,
        x_addr,
        MaybeRelocatable.fromFelt(Felt252.fromInt(u256, @intCast((x & std.math.maxInt(u128)) % STARKNET_PRIME))),
    );
    try vm.insertInMemory(allocator, try x_addr.addUint(1), MaybeRelocatable.fromFelt(Felt252.fromInt(u256, @intCast((x >> 128) % STARKNET_PRIME))));
}

const SPLIT_XX_PRIME: u256 = 57896044618658097711785492504343953926634992332820282019728792003956564819949;
const II: u256 = 19681161376707505956807079304988542015446066515923890162744021073123829784752;

pub fn isQuadResidue(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const x = try hint_utils.getIntegerFromVarName("x", vm, ids_data, ap_tracking);

    const value =
        if (x.isZero() or x.eql(Felt252.one()))
        x
    else if (x.powToInt((field_helper.felt252MaxValue().divRem(Felt252.two()))[0].toU256()).eql(Felt252.one()))
        x.sqrt() orelse Felt252.zero()
    else
        (try x.div(Felt252.three()))
            .sqrt() orelse Felt252.zero();

    try hint_utils.insertValueFromVarName(allocator, "y", MaybeRelocatable.fromFelt(value), vm, ids_data, ap_tracking);
}

fn divPrimeByBound(bound: Felt252) !Felt252 {
    return Felt252.fromInt(u256, STARKNET_PRIME / bound.toU256());
}

fn primeDivConstant(bound: u32) !u256 {
    return STARKNET_PRIME / bound;
}

test "MathUtils: splitXx run" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();

    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "x",
            .elems = &.{
                null,
                null,
            },
        },

        .{
            .name = "xx",
            .elems = &.{
                MaybeRelocatable.fromInt(u256, 7),
                MaybeRelocatable.fromInt(u256, 17),
            },
        },
    }, &vm);

    var hint_data = HintData.init(hint_codes.SPLIT_XX, ids_data, .{});
    defer hint_data.deinit();

    const hint_processor = HintProcessor{};

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Uint256.init(Felt252.fromInt(u256, 316161011683971866381321160306766491472), Felt252.fromInt(u256, 30265492890921847871084892076606437231)), try Uint256.fromVarName("x", &vm, ids_data, .{}));
}

test "MathUtils: isNn hint true" {
    const hint_code = "memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1";
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 5;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{1} },
    });

    _ = try vm.segments.addSegment();
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"a"});
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{0} }});
}

test "MathUtils: isNn hint false" {
    const hint_code = "memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1";
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 10;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 9 }, .{-1} },
    });

    _ = try vm.segments.addSegment();
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"a"});
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{1} }});
}

test "MathUtils: isNn hint border case" {
    const hint_code = "memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1";
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 5;

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    //Insert ids into memory
    try vm.insertInMemory(std.testing.allocator, Relocatable.init(1, 4), MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 3618502788666131213697322783095070105623107215331596699973092056135872020480).neg()));
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"a"});
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{0} }});
}

test "MathUtils: isNnOutOfRange hint true" {
    const hint_code = "memory[ap] = 0 if 0 <= ((-ids.a - 1) % PRIME) < range_check_builtin.bound else 1";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 5;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{-1} },
    });

    _ = try vm.segments.addSegment();
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"a"});
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{0} }});
}

test "MathUtils: isNnOutOfRange hint false" {
    const hint_code = "memory[ap] = 0 if 0 <= ((-ids.a - 1) % PRIME) < range_check_builtin.bound else 1";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 5;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{2} },
    });

    _ = try vm.segments.addSegment();
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"a"});
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{1} }});
}

test "MathUtils: assertLeFelt06 assertetion failed" {
    const hint_code = hint_codes.ASSERT_LE_FELT_V_0_6;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 2;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{17} },
        .{ .{ 1, 1 }, .{7} },
    });

    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "a", "b" });
    defer ids_data.deinit();

    //Execute the hint
    try std.testing.expectError(HintError.NonLeFelt252, testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined));
}

test "MathUtils: assertLeFelt08 assertetion failed" {
    const hint_code = hint_codes.ASSERT_LE_FELT_V_0_8;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 2;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{17} },
        .{ .{ 1, 1 }, .{7} },
    });

    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "a", "b" });
    defer ids_data.deinit();

    //Execute the hint
    try std.testing.expectError(HintError.NonLeFelt252, testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined));
}

test "MathUtils: isLeFelt hint true" {
    const hint_code = "memory[ap] = 0 if (ids.a % PRIME) <= (ids.b % PRIME) else 1";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 10;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 8 }, .{1} },
        .{ .{ 1, 9 }, .{2} },
    });

    _ = try vm.segments.addSegment();
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "a", "b" });
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{0} }});
}

test "MathUtils: slitInt valid" {
    const hint_code = "memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base\nassert res < ids.bound, f'split_int(): Limb {res} is out of range.'";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 4;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{10} },
        .{ .{ 1, 3 }, .{100} },
    });

    _ = try vm.segments.addSegment();
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "output", "value", "base", "bound" });
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 2, 0 }, .{2} }});
}

test "MathUtils: slitInt invalid" {
    const hint_code = "memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base\nassert res < ids.bound, f'split_int(): Limb {res} is out of range.'";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 4;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{100} },
        .{ .{ 1, 2 }, .{10000} },
        .{ .{ 1, 3 }, .{10} },
    });

    _ = try vm.segments.addSegment();
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "output", "value", "base", "bound" });
    defer ids_data.deinit();

    //Execute the hint
    try std.testing.expectError(HintError.SplitIntLimbOutOfRange, testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined));
}

test "MathUtils: isAddrBounded ok" {
    const hint_code = hint_codes.IS_ADDR_BOUNDED;

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(ADDR_BOUND, Felt252.fromInt(u256, 3618502788666131106986593281521497120414687020801267626233049500247285301000));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Initialize fp
    vm.run_context.fp = 2;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1809251394333067160431340899751024102169435851563236335319518532916477952000} },
    });
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "addr", "is_small" });
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, &constants, &exec_scopes);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 1 }, .{1} }});
}

test "MathUtils: isAddrBounded failed" {
    const hint_code = hint_codes.IS_ADDR_BOUNDED;

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(ADDR_BOUND, Felt252.fromInt(u256, 1));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Initialize fp
    vm.run_context.fp = 2;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{3618502788666131106986593281521497120414687020801267626233049500247285301000} },
    });
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "addr", "is_small" });
    defer ids_data.deinit();

    //Execute the hint
    try std.testing.expectError(HintError.AssertionFailed, testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, &constants, &exec_scopes));
}

test "MathUtils: is250bit valid" {
    const hint_code = "ids.is_250 = 1 if ids.addr < 2**250 else 0";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 2;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1152251} },
    });

    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "addr", "is_250" });
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 1 }, .{1} }});
}

test "MathUtils: is250bit invalid" {
    const hint_code = "ids.is_250 = 1 if ids.addr < 2**250 else 0";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Initialize fp
    vm.run_context.fp = 2;
    //Insert ids into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{3618502788666131106986593281521497120414687020801267626233049500247285301248} },
    });

    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "addr", "is_250" });
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_code, undefined, undefined);
    //Check that ap now contains true (0)
    try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 1 }, .{0} }});
}
