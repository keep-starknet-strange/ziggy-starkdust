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

const Int = @import("std").math.big.int.Managed;
const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

const fromBigInt = @import("../math/fields/starknet.zig").fromBigInt;

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

pub const Uint256 = struct {
    const Self = @This();

    low: Felt252,
    high: Felt252,

    pub fn fromBaseAddr(addr: Relocatable, vm: *CairoVM) !Self {
        return .{
            .low = vm.getFelt(addr) catch return HintError.IdentifierHasNoMember,
            .high = vm.getFelt(try addr.addUint(1)) catch return HintError.IdentifierHasNoMember,
        };
    }

    pub fn fromVarName(name: []const u8, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !Self {
        const base_addr = try hint_utils.getRelocatableFromVarName(name, vm, ids_data, ap_tracking);

        return try Self.fromBaseAddr(base_addr, vm);
    }

    pub fn init(low: Felt252, high: Felt252) Self {
        return .{
            .low = low,
            .high = high,
        };
    }

    pub fn insertFromVarName(self: Self, allocator: std.mem.Allocator, var_name: []const u8, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
        const addr = try hint_utils.getRelocatableFromVarName(var_name, vm, ids_data, ap_tracking);

        try vm.insertInMemory(allocator, addr, MaybeRelocatable.fromFelt(self.low));
        try vm.insertInMemory(allocator, try addr.addUint(1), MaybeRelocatable.fromFelt(self.high));
    }

    pub fn split(allocator: std.mem.Allocator, num: Int) !Self {
        var mask_low = try Int.initSet(allocator, std.math.maxInt(u128));
        defer mask_low.deinit();

        var low = try num.clone();
        defer low.deinit();

        try low.bitAnd(&num, &mask_low);

        var high = try Int.init(allocator);
        defer high.deinit();

        try high.shiftRight(&num, 128);

        return Self.init(try fromBigInt(allocator, low), try fromBigInt(allocator, high));
    }

    pub fn pack(self: Self, allocator: std.mem.Allocator) !Int {
        var result = try Int.initSet(allocator, self.high.toU256());
        errdefer result.deinit();

        try result.shiftLeft(&result, 128);
        try result.addScalar(&result, self.low.toU256());
        return result;
    }

    pub fn fromFelt(value: Felt252) Self {
        const high, const low = value.divRem(Felt252.pow2Const(128)) catch unreachable;

        return .{
            .high = high,
            .low = low,
        };
    }
};

// Implements hints:
// %{
//     sum_low = ids.a.low + ids.b.low
//     ids.carry_low = 1 if sum_low >= ids.SHIFT else 0
//     sum_high = ids.a.high + ids.b.high + ids.carry_low
//     ids.carry_high = 1 if sum_high >= ids.SHIFT else 0
// %}
// %{
//     sum_low = ids.a.low + ids.b.low
//     ids.carry_low = 1 if sum_low >= ids.SHIFT else 0
// %}
pub fn uint256Add(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    low_only: bool,
) !void {
    const shift = Felt252.pow2Const(128);

    const a = try Uint256.fromVarName("a", vm, ids_data, ap_tracking);
    const b = try Uint256.fromVarName("b", vm, ids_data, ap_tracking);
    const a_low = a.low;
    const b_low = b.low;

    // Main logic
    // sum_low = ids.a.low + ids.b.low
    // ids.carry_low = 1 if sum_low >= ids.SHIFT else 0
    const carry_low = Felt252.fromInt(u8, if (a_low.add(&b_low).cmp(&shift).compare(.gte)) 1 else 0);

    if (!low_only) {
        const a_high = a.high;
        const b_high = b.high;

        // Main logic
        // sum_high = ids.a.high + ids.b.high + ids.carry_low
        // ids.carry_high = 1 if sum_high >= ids.SHIFT else 0
        const carry_high = Felt252.fromInt(u8, if (a_high.add(&b_high).add(&carry_low).cmp(&shift).compare(.gte)) 1 else 0);

        try hint_utils.insertValueFromVarName(allocator, "carry_high", MaybeRelocatable.fromFelt(carry_high), vm, ids_data, ap_tracking);
    }

    try hint_utils.insertValueFromVarName(allocator, "carry_low", MaybeRelocatable.fromFelt(carry_low), vm, ids_data, ap_tracking);
}

// Implements hint:
// %{
//     res = ids.a + ids.b
//     ids.carry = 1 if res >= ids.SHIFT else 0
// %}
pub fn uint128Add(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const shift = Felt252.pow2Const(128);
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const b = try hint_utils.getIntegerFromVarName("b", vm, ids_data, ap_tracking);

    // Main logic
    // res = ids.a + ids.b
    // ids.carry = 1 if res >= ids.SHIFT else 0
    const carry = Felt252.fromInt(u8, if (a.add(&b).cmp(&shift).compare(.gte)) 1 else 0);

    try hint_utils.insertValueFromVarName(allocator, "carry", MaybeRelocatable.fromFelt(carry), vm, ids_data, ap_tracking);
}

// Implements hint:
// %{
//     def split(num: int, num_bits_shift: int = 128, length: int = 2):
//         a = []
//         for _ in range(length):
//             a.append( num & ((1 << num_bits_shift) - 1) )
//             num = num >> num_bits_shift
//         return tuple(a)

//     def pack(z, num_bits_shift: int = 128) -> int:
//         limbs = (z.low, z.high)
//         return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

//     a = pack(ids.a)
//     b = pack(ids.b)
//     res = (a - b)%2**256
//     res_split = split(res)
//     ids.res.low = res_split[0]
//     ids.res.high = res_split[1]
// %}
pub fn uint256Sub(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var a = try (try Uint256.fromVarName("a", vm, ids_data, ap_tracking)).pack(allocator);
    defer a.deinit();

    var b = try (try Uint256.fromVarName("b", vm, ids_data, ap_tracking)).pack(allocator);
    defer b.deinit();

    // Main logic:
    // res = (a - b)%2**256
    var res = if (a.order(b).compare(.gte)) blk: {
        var tmp = try Int.init(allocator);
        errdefer tmp.deinit();
        try tmp.sub(&a, &b);

        break :blk tmp;
    } else blk: {

        // wrapped a - b
        // b is limited to (CAIRO_PRIME - 1) << 128 which is 1 << (251 + 128 + 1)
        //                                         251: most significant felt bit
        //                                         128:     high field left shift
        //                                           1:       extra bit for limit
        var mod_256 = try Int.initSet(allocator, 1);
        errdefer mod_256.deinit();

        try mod_256.shiftLeft(&mod_256, 256);

        if (mod_256.order(b).compare(.gte)) {
            try mod_256.add(&mod_256, &a);
            try mod_256.sub(&mod_256, &b);

            break :blk mod_256;
        } else {
            var tmp = try Int.init(allocator);
            defer tmp.deinit();

            var lowered_b = try Int.init(allocator);
            defer lowered_b.deinit();

            try tmp.divFloor(&lowered_b, &b, &mod_256);

            // Repeat the logic from before
            if (a.order(lowered_b).compare(.gte)) {
                try mod_256.sub(&a, &lowered_b);

                break :blk mod_256;
            } else {
                try mod_256.add(&mod_256, &a);
                try mod_256.sub(&mod_256, &lowered_b);

                break :blk mod_256;
            }
        }
    };
    defer res.deinit();

    try (try Uint256.split(allocator, res)).insertFromVarName(allocator, "res", vm, ids_data, ap_tracking);
}

// Implements hint:
// %{
//     ids.low = ids.a & ((1<<64) - 1)
//     ids.high = ids.a >> 64
// %}
pub fn split64(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a = try hint_utils.getIntegerFromVarName("a", vm, ids_data, ap_tracking);
    const digits = a.toLeDigits();
    var bytes = [_]u8{0} ** 32;

    inline for (1..4) |i| {
        std.mem.writeInt(u64, bytes[(i - 1) * 8 .. i * 8], digits[i], .little);
    }

    const low = Felt252.fromInt(u64, digits[0]);
    const high = Felt252.fromBytesLe(bytes);

    try hint_utils.insertValueFromVarName(allocator, "high", MaybeRelocatable.fromFelt(high), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "low", MaybeRelocatable.fromFelt(low), vm, ids_data, ap_tracking);
}

// Implements hint:
// %{
//     from starkware.python.math_utils import isqrt
//     n = (ids.n.high << 128) + ids.n.low
//     root = isqrt(n)
//     assert 0 <= root < 2 ** 128
//     ids.root.low = root
//     ids.root.high = 0
// %}
pub fn uint256Sqrt(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    only_low: bool,
) !void {
    // todo use big int for this
    var n = try (try Uint256.fromVarName("n", vm, ids_data, ap_tracking)).pack(allocator);
    defer n.deinit();

    // Main logic
    // from starkware.python.math_utils import isqrt
    // n = (ids.n.high << 128) + ids.n.low
    // root = isqrt(n)
    // assert 0 <= root < 2 ** 128
    // ids.root.low = root
    // ids.root.high = 0

    var root = try Int.init(allocator);
    defer root.deinit();

    try root.sqrt(&n);

    if (root.bitCountAbs() > 128)
        return HintError.AssertionFailed;

    const root_field = try fromBigInt(allocator, root);

    if (only_low) {
        try hint_utils.insertValueFromVarName(allocator, "root", MaybeRelocatable.fromFelt(root_field), vm, ids_data, ap_tracking);
    } else {
        try Uint256.init(root_field, Felt252.zero()).insertFromVarName(allocator, "root", vm, ids_data, ap_tracking);
    }
}

// Implements hint:
// %{ memory[ap] = 1 if 0 <= (ids.a.high % PRIME) < 2 ** 127 else 0 %}
pub fn uint256SignedNn(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const a_addr = try hint_utils.getRelocatableFromVarName("a", vm, ids_data, ap_tracking);
    const a_high = try vm.getFelt(try a_addr.addUint(1));
    //Main logic
    //memory[ap] = 1 if 0 <= (ids.a.high % PRIME) < 2 ** 127 else 0
    const result: Felt252 =
        if (a_high.cmp(&Felt252.zero()).compare(.gte) and a_high.cmp(&Felt252.fromInt(u128, std.math.maxInt(i128))).compare(.lte))
        Felt252.one()
    else
        Felt252.zero();

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(result));
}

// Implements hint:
// %{
//     a = (ids.a.high << 128) + ids.a.low
//     div = (ids.div.high << 128) + ids.div.low
//     quotient, remainder = divmod(a, div)

//     ids.quotient.low = quotient & ((1 << 128) - 1)
//     ids.quotient.high = quotient >> 128
//     ids.remainder.low = remainder & ((1 << 128) - 1)
//     ids.remainder.high = remainder >> 128
// %}
pub fn uint256UnsignedDivRem(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    return uint256OffsetedUnsignedDivRem(allocator, vm, ids_data, ap_tracking, 0, 1);
}

// Implements hint:
// %{
//     a = (ids.a.high << 128) + ids.a.low
//     div = (ids.div.b23 << 128) + ids.div.b01
//     quotient, remainder = divmod(a, div)

//     ids.quotient.low = quotient & ((1 << 128) - 1)
//     ids.quotient.high = quotient >> 128
//     ids.remainder.low = remainder & ((1 << 128) - 1)
//     ids.remainder.high = remainder >> 128
// %}
pub fn uint256ExpandedUnsignedDivRem(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    return uint256OffsetedUnsignedDivRem(allocator, vm, ids_data, ap_tracking, 1, 3);
}

pub fn uint256OffsetedUnsignedDivRem(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    div_offset_low: usize,
    div_offset_high: usize,
) !void {
    const a = try Uint256.fromVarName("a", vm, ids_data, ap_tracking);
    const a_low = a.low;
    const a_high = a.high;

    const div_addr = try hint_utils.getRelocatableFromVarName("div", vm, ids_data, ap_tracking);
    const div_low = try vm.getFelt(try div_addr.addUint(div_offset_low));
    const div_high = try vm.getFelt(try div_addr.addUint(div_offset_high));

    //Main logic
    //a = (ids.a.high << 128) + ids.a.low
    //div = (ids.div.high << 128) + ids.div.low
    //quotient, remainder = divmod(a, div)

    //ids.quotient.low = quotient & ((1 << 128) - 1)
    //ids.quotient.high = quotient >> 128
    //ids.remainder.low = remainder & ((1 << 128) - 1)
    //ids.remainder.high = remainder >> 128

    var a_high_big = try a_high.toStdBigInt(allocator);
    defer a_high_big.deinit();

    var a_low_big = try a_low.toStdBigInt(allocator);
    defer a_low_big.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();
    var tmp2 = try Int.init(allocator);
    defer tmp2.deinit();

    var div_high_big = try div_high.toStdBigInt(allocator);
    defer div_high_big.deinit();

    var div_low_big = try div_low.toStdBigInt(allocator);
    defer div_low_big.deinit();

    try tmp.shiftLeft(&a_high_big, 128);
    // a_shifted
    try tmp.add(&tmp, &a_low_big);

    try tmp2.shiftLeft(&div_high_big, 128);
    // div
    try tmp2.add(&tmp2, &div_low_big);

    var quotient = try Int.init(allocator);
    defer quotient.deinit();

    var remainder = try Int.init(allocator);
    defer remainder.deinit();
    //a and div will always be positive numbers
    //Then, Rust div_rem equals Python divmod
    try quotient.divTrunc(&remainder, &tmp, &tmp2);

    const quotient_uint256 = try Uint256.split(allocator, quotient);
    const remainder_uint256 = try Uint256.split(allocator, remainder);

    try quotient_uint256.insertFromVarName(allocator, "quotient", vm, ids_data, ap_tracking);
    try remainder_uint256.insertFromVarName(allocator, "remainder", vm, ids_data, ap_tracking);
}

// Implements Hint:
// %{
// a = (ids.a.high << 128) + ids.a.low
// b = (ids.b.high << 128) + ids.b.low
// div = (ids.div.high << 128) + ids.div.low
// quotient, remainder = divmod(a * b, div)

// ids.quotient_low.low = quotient & ((1 << 128) - 1)
// ids.quotient_low.high = (quotient >> 128) & ((1 << 128) - 1)
// ids.quotient_high.low = (quotient >> 256) & ((1 << 128) - 1)
// ids.quotient_high.high = quotient >> 384
// ids.remainder.low = remainder & ((1 << 128) - 1)
// ids.remainder.high = remainder >> 128
// %}
pub fn uint256MulDivMod(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Extract variables
    const a_addr = try hint_utils.getRelocatableFromVarName("a", vm, ids_data, ap_tracking);
    const b_addr = try hint_utils.getRelocatableFromVarName("b", vm, ids_data, ap_tracking);
    const div_addr = try hint_utils.getRelocatableFromVarName("div", vm, ids_data, ap_tracking);
    const quotient_low_addr =
        try hint_utils.getRelocatableFromVarName("quotient_low", vm, ids_data, ap_tracking);
    const quotient_high_addr =
        try hint_utils.getRelocatableFromVarName("quotient_high", vm, ids_data, ap_tracking);
    const remainder_addr = try hint_utils.getRelocatableFromVarName("remainder", vm, ids_data, ap_tracking);

    const a_low = try vm.getFelt(a_addr);
    const a_high = try vm.getFelt(try a_addr.addUint(1));
    const b_low = try vm.getFelt(b_addr);
    const b_high = try vm.getFelt(try b_addr.addUint(1));
    const div_low = try vm.getFelt(div_addr);
    const div_high = try vm.getFelt(try div_addr.addUint(1));

    // Main Logic
    // TODO: optimize use bigint instead of u512

    var tmp = try a_high.toStdBigInt(allocator);
    defer tmp.deinit();

    try tmp.shiftLeft(&tmp, 128);

    var tmp1 = try a_low.toStdBigInt(allocator);
    defer tmp1.deinit();

    try tmp.add(&tmp, &tmp1);

    var a = try tmp.clone();
    defer a.deinit();

    try tmp.set(b_high.toU256());
    try tmp.shiftLeft(&tmp, 128);

    try tmp1.set(b_low.toU256());

    var b = try Int.init(allocator);
    defer b.deinit();

    try b.add(&tmp, &tmp1);

    var div = try div_high.toStdBigInt(allocator);
    defer div.deinit();

    try div.shiftLeft(&div, 128);

    try tmp.set(div_low.toU256());

    try div.add(&div, &tmp);

    if (div.eqlZero()) {
        return MathError.DividedByZero;
    }

    try tmp1.mul(&a, &b);

    // tmp quotient, tmp1 remaninder
    try tmp.divFloor(&tmp1, &tmp1, &div);

    var maxU128 = try Int.initSet(allocator, std.math.maxInt(u128));
    defer maxU128.deinit();

    // ids.quotient_low.low
    try a.bitAnd(&tmp, &maxU128);
    try vm.insertInMemory(
        allocator,
        quotient_low_addr,
        MaybeRelocatable.fromFelt(try fromBigInt(allocator, a)),
    );
    // ids.quotient_low.high
    try a.shiftRight(&tmp, 128);
    try a.bitAnd(&a, &maxU128);
    try vm.insertInMemory(
        allocator,
        try quotient_low_addr.addUint(1),
        MaybeRelocatable.fromFelt(try fromBigInt(allocator, a)),
    );
    // ids.quotient_high.low
    try a.shiftRight(&tmp, 256);
    try a.bitAnd(&a, &maxU128);
    try vm.insertInMemory(
        allocator,
        quotient_high_addr,
        MaybeRelocatable.fromFelt(try fromBigInt(allocator, a)),
    );
    // ids.quotient_high.high
    try a.shiftRight(&tmp, 384);
    try vm.insertInMemory(allocator, try quotient_high_addr.addUint(1), MaybeRelocatable.fromFelt(try fromBigInt(allocator, a)));
    //ids.remainder.low
    try a.bitAnd(&tmp1, &maxU128);
    try vm.insertInMemory(
        allocator,
        remainder_addr,
        MaybeRelocatable.fromFelt(try fromBigInt(allocator, a)),
    );
    //ids.remainder.high
    try a.shiftRight(&tmp1, 128);
    try vm.insertInMemory(
        allocator,
        try remainder_addr.addUint(1),
        MaybeRelocatable.fromFelt(try fromBigInt(allocator, a)),
    );
}

test "Uint256: uint256AddLowOnly ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", -6 }, .{ "b", -4 }, .{ "carry_low", 2 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{2} },
        .{ .{ 1, 5 }, .{3} },
        .{ .{ 1, 6 }, .{4} },
        .{ .{ 1, 7 }, .{340282366920938463463374607431768211455} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init("sum_low = ids.a.low + ids.b.low\nids.carry_low = 1 if sum_low >= ids.SHIFT else 0", ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.zero(), try vm.getFelt(Relocatable.init(1, 12)));
}

test "Uint256: uint256Add ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", -6 }, .{ "b", -4 }, .{ "carry_low", 2 }, .{ "carry_high", 3 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{2} },
        .{ .{ 1, 5 }, .{3} },
        .{ .{ 1, 6 }, .{4} },
        .{ .{ 1, 7 }, .{340282366920938463463374607431768211455} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_ADD, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.zero(), try vm.getFelt(Relocatable.init(1, 12)));
    try std.testing.expectEqual(Felt252.one(), try vm.getFelt(Relocatable.init(1, 13)));
}

test "Uint256: uint128Add ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", 0 }, .{ "b", 1 }, .{ "carry", 2 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{180141183460469231731687303715884105727} },
        .{ .{ 1, 1 }, .{180141183460469231731687303715884105727} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT128_ADD, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.one(), try vm.getFelt(Relocatable.init(1, 2)));
}

test "Uint256: uint256Sub b high gt 256 gt a" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", 0 }, .{ "b", 2 }, .{ "res", 4 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{340282366920938463463374607431768211457} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SUB, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u8, 1), try vm.getFelt(Relocatable.init(1, 4)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 340282366920938463463374607431768211455), try vm.getFelt(Relocatable.init(1, 5)));
}

test "Uint256: uint256Sub negative ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", 0 }, .{ "b", 2 }, .{ "res", 4 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1001} },
        .{ .{ 1, 1 }, .{6687} },
        .{ .{ 1, 2 }, .{12179} },
        .{ .{ 1, 3 }, .{13044} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SUB, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 340282366920938463463374607431768200278), try vm.getFelt(Relocatable.init(1, 4)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 340282366920938463463374607431768205098), try vm.getFelt(Relocatable.init(1, 5)));
}

test "Uint256: uint256Sub nonnegative ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", 0 }, .{ "b", 2 }, .{ "res", 4 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{12179} },
        .{ .{ 1, 1 }, .{13044} },
        .{ .{ 1, 2 }, .{1001} },
        .{ .{ 1, 3 }, .{6687} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SUB, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 11178), try vm.getFelt(Relocatable.init(1, 4)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 6357), try vm.getFelt(Relocatable.init(1, 5)));
}

test "Uint256: uint256Sub missing number" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "a", 0 },
        },
    );
    defer ids_data.deinit();

    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SUB, ids_data, .{});

    try std.testing.expectError(HintError.IdentifierHasNoMember, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
    //Check hint memory inserts
}

test "Uint256: uint256Sub b high gt 256 lte a" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", 0 }, .{ "b", 2 }, .{ "res", 4 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{340282366920938463463374607431768211456} },
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{0} },
        .{ .{ 1, 3 }, .{340282366920938463463374607431768211457} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SUB, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u8, 0), try vm.getFelt(Relocatable.init(1, 4)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 0), try vm.getFelt(Relocatable.init(1, 5)));
}

test "Uint256: split64 ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", -3 }, .{ "high", 1 }, .{ "low", 0 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 7 }, .{850981239023189021389081239089023} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.SPLIT_64, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 7249717543555297151), try vm.getFelt(Relocatable.init(1, 10)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 46131785404667), try vm.getFelt(Relocatable.init(1, 11)));
}

test "Uint256: split64 with big a" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{ .{ "a", -3 }, .{ "high", 1 }, .{ "low", 0 } },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 7 }, .{400066369019890261321163226850167045262} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.SPLIT_64, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 2279400676465785998), try vm.getFelt(Relocatable.init(1, 10)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 21687641321487626429), try vm.getFelt(Relocatable.init(1, 11)));
}

test "Uint256: uint256Sqrt ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 5;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "n", -5 },
            .{ "root", 0 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{17} },
        .{ .{ 1, 1 }, .{7} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SQRT, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u128, 48805497317890012913), try vm.getFelt(Relocatable.init(1, 5)));
    try std.testing.expectEqual(Felt252.fromInt(u128, 0), try vm.getFelt(Relocatable.init(1, 6)));
}

test "Uint256: uint256Sqrt felt ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "n", 0 },
            .{ "root", 2 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{879232} },
        .{ .{ 1, 1 }, .{135906} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SQRT_FELT, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 6800471701195223914689), try vm.getFelt(Relocatable.init(1, 2)));
}

test "Uint256: uint256Sqrt assert error" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 5;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "n", -5 },
            .{ "root", 0 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0} },
        .{ .{ 1, 1 }, .{340282366920938463463374607431768211458} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SQRT, ids_data, .{});

    try std.testing.expectError(HintError.AssertionFailed, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}

test "Uint256: signedNN ok result one" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 5;
    vm.run_context.fp = 4;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "a", -4 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{3618502788666131213697322783095070105793248398792065931704779359851756126208} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SIGNED_NN, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 1), try vm.getFelt(Relocatable.init(1, 5)));
}

test "Uint256: signedNN ok result zero" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 5;
    vm.run_context.fp = 4;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "a", -4 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{3618502788666131213697322783095070105793248398792065931704779359851756126209} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_SIGNED_NN, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 0), try vm.getFelt(Relocatable.init(1, 5)));
}

test "Uint256: unsigned div rem ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "a", -6 },
            .{ "div", -4 },
            .{ "quotient", 0 },
            .{ "remainder", 2 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 4 }, .{89} },
        .{ .{ 1, 5 }, .{72} },
        .{ .{ 1, 6 }, .{3} },
        .{ .{ 1, 7 }, .{7} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_UNSIGNED_DIV_REM, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 10), try vm.getFelt(Relocatable.init(1, 10)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 0), try vm.getFelt(Relocatable.init(1, 11)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 59), try vm.getFelt(Relocatable.init(1, 12)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 2), try vm.getFelt(Relocatable.init(1, 13)));
}

test "Uint256: unsigned div rem expanded ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 0;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "a", 0 },
            .{ "div", 2 },
            .{ "quotient", 7 },
            .{ "remainder", 9 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{89} },
        .{ .{ 1, 1 }, .{72} },
        .{ .{ 1, 2 }, .{55340232221128654848} },
        .{ .{ 1, 3 }, .{3} },
        .{ .{ 1, 4 }, .{129127208515966861312} },
        .{ .{ 1, 5 }, .{7} },
        .{ .{ 1, 6 }, .{0} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_EXPANDED_UNSIGNED_DIV_REM, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 10), try vm.getFelt(Relocatable.init(1, 7)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 0), try vm.getFelt(Relocatable.init(1, 8)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 59), try vm.getFelt(Relocatable.init(1, 9)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 2), try vm.getFelt(Relocatable.init(1, 10)));
}

test "Uint256: mul div mod ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsNonContinuousIdsData(
        std.testing.allocator,
        &.{
            .{ "a", -8 },
            .{ "b", -6 },
            .{ "div", -4 },
            .{ "quotient_low", 0 },
            .{ "quotient_high", 2 },
            .{ "remainder", 4 },
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 2 }, .{89} },
        .{ .{ 1, 3 }, .{72} },
        .{ .{ 1, 4 }, .{3} },
        .{ .{ 1, 5 }, .{7} },
        .{ .{ 1, 6 }, .{107} },
        .{ .{ 1, 7 }, .{114} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.UINT256_MUL_DIV_MOD, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    //Check hint memory inserts
    try std.testing.expectEqual(Felt252.fromInt(u256, 143276786071974089879315624181797141668), try vm.getFelt(Relocatable.init(1, 10)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 4), try vm.getFelt(Relocatable.init(1, 11)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 0), try vm.getFelt(Relocatable.init(1, 12)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 0), try vm.getFelt(Relocatable.init(1, 13)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 322372768661941702228460154409043568767), try vm.getFelt(Relocatable.init(1, 14)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 101), try vm.getFelt(Relocatable.init(1, 15)));
}
