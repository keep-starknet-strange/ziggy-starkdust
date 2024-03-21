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
    const value = if (range_check_builtin.bound) |bound| if (a.ge(bound)) Felt252.one() else Felt252.zero() else Felt252.zero();

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

    const value = if (range_check_builtin.bound) |bound| if (bound.sub(a.add(Felt252.one())).lt(bound)) Felt252.zero() else Felt252.one() else Felt252.zero();

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(value));
}

pub fn assertLeFeltV06(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const b = try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking);

    if (a.gt(b)) {
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

    if (a.gt(b)) return HintError.NonLeFelt252;

    const bound = (try vm.getRangeCheckBuiltin()).bound orelse Felt252.zero();
    const small_inputs =
        if (a.lt(bound) and b.sub(a).lt(bound)) Felt252.one() else Felt252.zero();

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
    const a_lsb = (try a.divRem(two)).r;
    const b_lsb = (try b.divRem(two)).r;

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

    const value = if (a_mod.gt(b_mod)) Felt252.one() else Felt252.zero();

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
    const res = (try value.divRem(base)).r;

    if (res.gt(bound))
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

    const addr_bound = (constants
        .get(ADDR_BOUND) orelse return HintError.MissingConstant).toInteger();

    const lower_bound: u256 = 1 << 250;
    const upper_bound: u256 = 1 << 251;

    // assert (2**250 < ADDR_BOUND <= 2**251) and (2 * 2**250 < PRIME) and (
    //      ADDR_BOUND * 2 > PRIME), \
    //      'normalize_address() cannot be used with the current constants.'
    // The second check is not needed, as it's true for the CAIRO_PRIME
    if (!(lower_bound < addr_bound and addr_bound <= upper_bound or (addr_bound << 1) > STARKNET_PRIME))
        return HintError.AssertionFailed;

    // Main logic: ids.is_small = 1 if ids.addr < ADDR_BOUND else 0
    const is_small = if (addr.lt(Felt252.fromInt(u256, addr_bound))) Felt252.one() else Felt252.zero();

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
    const is_250 = if (addr.numBits() <= 250) Felt252.one() else Felt252.zero();

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

    const xx = xx_u.low.toInteger() + xx_u.high.mul(Felt252.pow2Const(128)).toInteger();

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
        MaybeRelocatable.fromFelt(Felt252.fromInt(u512, x & std.math.maxInt(u128))),
    );
    try vm.insertInMemory(allocator, try x_addr.addUint(1), MaybeRelocatable.fromFelt(Felt252.fromInt(u512, x >> 128)));
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

    std.log.debug("salammm {any}\n", .{x});
    if (x.isZero() or x.equal(Felt252.one())) {
        try hint_utils.insertValueFromVarName(allocator, "y", MaybeRelocatable.fromFelt(x), vm, ids_data, ap_tracking);
        // } else if Pow::pow(felt_to_biguint(x), &(&*CAIRO_PRIME >> 1_u32)).is_one() {
    } else if (x.pow((try Felt252.Max.divRem(Felt252.two())).q.toInteger()).equal(Felt252.one())) {
        try hint_utils.insertValueFromVarName(allocator, "y", MaybeRelocatable.fromFelt(x.sqrt() orelse Felt252.zero()), vm, ids_data, ap_tracking);
    } else {
        try hint_utils.insertValueFromVarName(
            allocator,
            "y",
            MaybeRelocatable.fromFelt((try x.div(Felt252.three()))
                .sqrt() orelse Felt252.zero()),
            vm,
            ids_data,
            ap_tracking,
        );
    }
}

fn divPrimeByBound(bound: Felt252) !Felt252 {
    return Felt252.fromInt(u256, STARKNET_PRIME / bound.toInteger());
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
