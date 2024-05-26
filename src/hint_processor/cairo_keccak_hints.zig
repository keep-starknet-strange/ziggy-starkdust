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
const MemoryError = @import("../vm/error.zig").MemoryError;

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

// Constants in package "starkware.cairo.common.cairo_keccak.keccak".
pub const BYTES_IN_WORD = "starkware.cairo.common.cairo_keccak.keccak.BYTES_IN_WORD";

pub const KECCAK_FULL_RATE_IN_BYTES_CAIRO_KECCAK = "starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_BYTES";
pub const KECCAK_FULL_RATE_IN_BYTES_BUILTIN_KECCAK = "starkware.cairo.common.builtin_keccak.keccak.KECCAK_FULL_RATE_IN_BYTES";
pub const KECCAK_FULL_RATE_IN_BYTES = "KECCAK_FULL_RATE_IN_BYTES";

pub const KECCAK_STATE_SIZE_FELTS = "starkware.cairo.common.cairo_keccak.keccak.KECCAK_STATE_SIZE_FELTS";

pub const BLOCK_SIZE = "starkware.cairo.common.cairo_keccak.packed_keccak.BLOCK_SIZE";

// Implements hint:
//     %{
//       segments.write_arg(ids.inputs, [ids.low % 2 ** 64, ids.low // 2 ** 64])
//       segments.write_arg(ids.inputs + 2, [ids.high % 2 ** 64, ids.high // 2 ** 64])
//     %}
pub fn keccakWriteArgs(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const inputs_ptr = try hint_utils.getPtrFromVarName("inputs", vm, ids_data, ap_tracking);

    const low = try hint_utils.getIntegerFromVarName("low", vm, ids_data, ap_tracking);
    const high = try hint_utils.getIntegerFromVarName("high", vm, ids_data, ap_tracking);

    const bound = Felt252.pow2Const(64);
    const d1, const d0 = low.divRem(bound);
    const d3, const d2 = high.divRem(bound);

    var arg = std.ArrayList(Felt252).init(allocator);
    defer arg.deinit();

    try arg.appendSlice(&.{
        d0, d1, d2, d3,
    });

    _ = try vm.segments.writeArg(std.ArrayList(Felt252), inputs_ptr, &arg);
}

// Implements hint:
//     Cairo code:
//     if nondet %{ ids.n_bytes < ids.BYTES_IN_WORD %} != 0:

//     Compiled code:
//     memory[ap] = to_felt_or_relocatable(ids.n_bytes < ids.BYTES_IN_WORD)
pub fn compareBytesInWordNondet(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const n_bytes = try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking);

    // This works fine, but it should be checked for a performance improvement.
    // One option is to try to convert n_bytes into usize, with failure to do so simply
    // making value be 0 (if it can't convert then it's either negative, which can't be in Cairo memory
    // or too big, which also means n_bytes > BYTES_IN_WORD). The other option is to exctract
    // Felt252::from(BYTES_INTO_WORD) into a lazy_static!
    const bytes_in_word = constants
        .get(BYTES_IN_WORD) orelse return HintError.MissingConstant;

    const value = if (n_bytes.cmp(&bytes_in_word).compare(.lt)) Felt252.one() else Felt252.zero();

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(value));
}

// Implements hint:
//     Cairo code:
//     if nondet %{ ids.n_bytes >= ids.KECCAK_FULL_RATE_IN_BYTES %} != 0:

//     Compiled code:
//     "memory[ap] = to_felt_or_relocatable(ids.n_bytes >= ids.KECCAK_FULL_RATE_IN_BYTES)"
pub fn compareKeccakFullRateInBytesNondet(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const n_bytes = try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking);

    const keccak_full_rate_in_bytes = constants
        .get(KECCAK_FULL_RATE_IN_BYTES_CAIRO_KECCAK) orelse constants.get(KECCAK_FULL_RATE_IN_BYTES_BUILTIN_KECCAK) orelse return HintError.MissingConstant;

    const value = if (n_bytes.cmp(&keccak_full_rate_in_bytes).compare(.gte)) Felt252.one() else Felt252.zero();
    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(value));
}

// Implements hints:
//     %{
//         from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         assert 0 <= _keccak_state_size_felts < 100

//         output_values = keccak_func(memory.get_range(
//             ids.keccak_ptr - _keccak_state_size_felts, _keccak_state_size_felts))
//         segments.write_arg(ids.keccak_ptr, output_values)
//     %}
//     %{
//         from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         assert 0 <= _keccak_state_size_felts < 100

//         output_values = keccak_func(memory.get_range(
//             ids.keccak_ptr - _keccak_state_size_felts, _keccak_state_size_felts))
//         segments.write_arg(ids.keccak_ptr, output_values)
//     %}
pub fn blockPermutationV1(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const keccak_state_size_felts = try (constants
        .get(KECCAK_STATE_SIZE_FELTS) orelse return HintError.MissingConstant).toInt(u64);

    if (keccak_state_size_felts >= 100)
        return HintError.InvalidKeccakStateSizeFelt252s;

    const keccak_ptr = try hint_utils.getPtrFromVarName("keccak_ptr", vm, ids_data, ap_tracking);

    const values = try vm.getRange(
        try keccak_ptr.subUint(keccak_state_size_felts),
        keccak_state_size_felts,
    );
    defer values.deinit();

    const u64_values = try maybeRelocVecToU64Array(allocator, values.items);
    defer u64_values.deinit();

    if (u64_values.items.len != 25) {
        return error.WrongMaybeRelocVec;
    }

    // this function of the keccak crate is the one used instead of keccak_func from
    // keccak_utils.py
    var hash_state: std.crypto.core.keccak.KeccakF(1600) = .{
        .st = u64_values.items[0..25].*,
    };

    hash_state.permuteR(24);

    var bigint_values = try u64ArrayToMayberelocatableVec(allocator, hash_state.st[0..]);
    defer bigint_values.deinit();

    _ = try vm.segments.writeArg(std.ArrayList(MaybeRelocatable), keccak_ptr, &bigint_values);
}

// Implements hint:
//     %{
//         ids.full_word = int(ids.n_bytes >= 8)
//     %}
pub fn cairoKeccakIsFullWord(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const n_bytes = (try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking)).toInt(usize) catch 8;

    const full_word = if (n_bytes >= 8) Felt252.one() else Felt252.zero();
    try hint_utils.insertValueFromVarName(allocator, "full_word", MaybeRelocatable.fromFelt(full_word), vm, ids_data, ap_tracking);
}

// Implements hint:
//     %{
//         from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         assert 0 <= _keccak_state_size_felts < 100
//         output_values = keccak_func(memory.get_range(
//             ids.keccak_ptr_start, _keccak_state_size_felts))
//         segments.write_arg(ids.output, output_values)
//     %}
pub fn blockPermutationV2(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const keccak_state_size_felts = try (constants
        .get(KECCAK_STATE_SIZE_FELTS) orelse return HintError.MissingConstant).toInt(usize);

    if (keccak_state_size_felts >= 100) {
        return HintError.InvalidKeccakStateSizeFelt252s;
    }

    const keccak_ptr = try hint_utils.getPtrFromVarName("keccak_ptr_start", vm, ids_data, ap_tracking);

    const values = try vm.getRange(keccak_ptr, keccak_state_size_felts);
    const u64_values = try maybeRelocVecToU64Array(allocator, values.items);

    if (u64_values.items.len != 25) {
        return error.WrongMaybeRelocVec;
    }

    // this function of the keccak crate is the one used instead of keccak_func from
    // keccak_utils.py
    var hash_state: std.crypto.core.keccak.KeccakF(1600) = .{
        .st = u64_values.items[0..25].*,
    };

    hash_state.permuteR(24);

    var bigint_values = try u64ArrayToMayberelocatableVec(allocator, hash_state.st[0..]);
    defer bigint_values.deinit();

    const output = try hint_utils.getPtrFromVarName("output", vm, ids_data, ap_tracking);

    _ = try vm.segments.writeArg(std.ArrayList(MaybeRelocatable), output, &bigint_values);
}

fn cairoKeccakFinalize(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
    block_size_limit: usize,
) !void {
    const keccak_state_size_felts = try (constants
        .get(KECCAK_STATE_SIZE_FELTS) orelse return HintError.MissingConstant).toInt(usize);
    const block_size = try (constants
        .get(BLOCK_SIZE) orelse return HintError.MissingConstant).toInt(usize);

    if (keccak_state_size_felts >= 100) return HintError.InvalidKeccakStateSizeFelt252s;

    if (block_size >= block_size_limit)
        return HintError.InvalidBlockSize;

    // this function of the keccak crate is the one used instead of keccak_func from
    // keccak_utils.py
    var hash_state: std.crypto.core.keccak.KeccakF(1600) = .{};

    hash_state.permuteR(24);

    var padding = std.ArrayList(MaybeRelocatable).init(allocator);
    defer padding.deinit();

    try padding.appendNTimes(MaybeRelocatable.fromFelt(Felt252.zero()), keccak_state_size_felts);
    try padding.appendSlice((try u64ArrayToMayberelocatableVec(allocator, hash_state.st[0..])).items);

    const base_padding = try padding.clone();

    for (0..(block_size - 1)) |_| {
        try padding.appendSlice(base_padding.items);
    }

    const keccak_ptr_end = try hint_utils.getPtrFromVarName("keccak_ptr_end", vm, ids_data, ap_tracking);

    _ = try vm.segments.writeArg(std.ArrayList(MaybeRelocatable), keccak_ptr_end, &padding);
}

// Implements hint:
//     %{
//         # Add dummy pairs of input and output.
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         _block_size = int(ids.BLOCK_SIZE)
//         assert 0 <= _keccak_state_size_felts < 100
//         assert 0 <= _block_size < 10
//         inp = [0] * _keccak_state_size_felts
//         padding = (inp + keccak_func(inp)) * _block_size
//         segments.write_arg(ids.keccak_ptr_end, padding)
//     %}
pub fn cairoKeccakFinalizeV1(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    try cairoKeccakFinalize(allocator, vm, ids_data, ap_tracking, constants, 10);
}

// Implements hint:
//     %{
//         # Add dummy pairs of input and output.
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         _block_size = int(ids.BLOCK_SIZE)
//         assert 0 <= _keccak_state_size_felts < 100
//         assert 0 <= _block_size < 1000
//         inp = [0] * _keccak_state_size_felts
//         padding = (inp + keccak_func(inp)) * _block_size
//         segments.write_arg(ids.keccak_ptr_end, padding)
//     %}
pub fn cairoKeccakFinalizeV2(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    try cairoKeccakFinalize(allocator, vm, ids_data, ap_tracking, constants, 1000);
}

// Helper function to transform a vector of MaybeRelocatables into a vector
// of u64. Raises error if there are None's or if MaybeRelocatables are not Bigints.
pub fn maybeRelocVecToU64Array(allocator: std.mem.Allocator, vec: []const ?MaybeRelocatable) !std.ArrayList(u64) {
    var array = std.ArrayList(u64).init(allocator);
    errdefer array.deinit();

    for (vec) |maybe_relocatable| {
        if (maybe_relocatable) |n| {
            switch (n) {
                .felt => |num| try array.append(try num.toInt(u64)),
                else => {},
            }
        } else {
            return CairoVMError.ExpectedIntAtRange;
        }
    }

    return array;
}

pub fn u64ArrayToMayberelocatableVec(allocator: std.mem.Allocator, array: []const u64) !std.ArrayList(MaybeRelocatable) {
    var arr = std.ArrayList(MaybeRelocatable).init(allocator);
    errdefer arr.deinit();

    for (array) |v| try arr.append(MaybeRelocatable.fromInt(u64, v));

    return arr;
}

test "CairoKeccakHints: is full word" {
    const cases: []const struct { i128, usize } = &.{
        .{ 0, 0 },
        .{ 1, 0 },
        .{ 7, 0 },
        .{ 8, 1 },
        .{ 16, 1 },
        .{ std.math.maxInt(usize), 1 },
        .{ std.math.maxInt(i128), 1 },
    };

    const hint_code = "ids.full_word = int(ids.n_bytes >= 8)";
    inline for (cases) |case| {
        errdefer {
            std.log.err("test_case failed: {any}\n", .{case});
        }
        var vm = try CairoVM.init(std.testing.allocator, .{});
        defer vm.deinit();
        defer vm.segments.memory.deinitData(std.testing.allocator);

        try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

        try vm.segments.memory.setUpMemory(std.testing.allocator, .{
            .{ .{ 1, 1 }, .{case[0]} },
        });
        vm.run_context.fp = 2;

        const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "full_word", "n_bytes" });

        var hint_data = HintData.init(hint_code, ids_data, .{});
        defer hint_data.deinit();

        var hint_processor = HintProcessor{};

        try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

        try testing_utils.checkMemory(vm.segments.memory, .{.{ .{ 1, 0 }, .{case[1]} }});
    }
}

test "CairoKeccakHints: writeArgs valid" {
    const hint_code = "segments.write_arg(ids.inputs, [ids.low % 2 ** 64, ids.low // 2 ** 64])\nsegments.write_arg(ids.inputs + 2, [ids.high % 2 ** 64, ids.high // 2 ** 64])";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{233} },
        .{ .{ 1, 1 }, .{351} },
        .{ .{ 1, 2 }, .{ 2, 0 } },
        .{ .{ 2, 4 }, .{5} },
    });
    vm.run_context.fp = 3;

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "low", "high", "inputs" });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    var hint_processor = HintProcessor{};

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
}

test "CairoKeccakHints: writeArgs error" {
    const hint_code = "segments.write_arg(ids.inputs, [ids.low % 2 ** 64, ids.low // 2 ** 64])\nsegments.write_arg(ids.inputs + 2, [ids.high % 2 ** 64, ids.high // 2 ** 64])";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{233} },
        .{ .{ 1, 1 }, .{351} },
        .{ .{ 1, 2 }, .{ 2, 0 } },
    });
    vm.run_context.fp = 3;

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "low", "high", "inputs" });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    var hint_processor = HintProcessor{};

    try std.testing.expectError(MemoryError.UnallocatedSegment, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}

test "CairoKeccakHints: compareBytesInWordNondet valid" {
    const hint_code = "memory[ap] = to_felt_or_relocatable(ids.n_bytes < ids.BYTES_IN_WORD)";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{24} },
    });
    _ = try vm.segments.addSegment();

    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.fp = 1;
    vm.run_context.ap = 1;

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n_bytes",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    var hint_processor = HintProcessor{};

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(BYTES_IN_WORD, Felt252.fromInt(u8, 136));

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, &exec_scopes);

    try std.testing.expectEqual(Felt252.one(), try vm.getFelt(vm.run_context.getAP()));
}

test "CairoKeccakHints: compareKeccakFullRateInBytesNondet valid" {
    const hint_code = "memory[ap] = to_felt_or_relocatable(ids.n_bytes >= ids.KECCAK_FULL_RATE_IN_BYTES)";

    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{240} },
    });
    _ = try vm.segments.addSegment();

    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.fp = 1;
    vm.run_context.ap = 1;

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n_bytes",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    var hint_processor = HintProcessor{};

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(KECCAK_FULL_RATE_IN_BYTES_CAIRO_KECCAK, Felt252.fromInt(u16, 5556));

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, &exec_scopes);

    try std.testing.expectEqual(Felt252.zero(), try vm.getFelt(vm.run_context.getAP()));
}

test "CairoKeccakHints: blockPermutation valid" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    _ = try vm.segments.addSegment();
    const keccak_ptr = try vm.segments.addSegment();

    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "keccak_ptr",
            .elems = &.{MaybeRelocatable.fromRelocatable(try keccak_ptr.addUint(26))},
        },
    }, &vm);

    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer data.deinit();

    try data.appendNTimes(MaybeRelocatable.fromFelt(Felt252.zero()), 25);

    _ = try vm.segments.loadData(std.testing.allocator, try keccak_ptr.addUint(1), data.items);

    var hint_data = HintData.init(hint_codes.BLOCK_PERMUTATION, ids_data, .{});
    defer hint_data.deinit();

    var hint_processor = HintProcessor{};

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(KECCAK_STATE_SIZE_FELTS, Felt252.fromInt(u8, 25));

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, &exec_scopes);

    // try std.testing.expectEqual(Felt252.one(), try vm.getFelt(vm.run_context.getAP()));
}
