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
const testing_utils = @import("testing_utils.zig");
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

const sha256 = @import("../math/crypto/sha256.zig");

const feltToU32 = @import("blake2s_utils.zig").feltToU32;

const SHA256_STATE_SIZE_FELTS: usize = 8;
const BLOCK_SIZE: usize = 7;
const IV: [SHA256_STATE_SIZE_FELTS]u32 = .{
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
};

pub fn sha256Input(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const n_bytes = try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking);

    try hint_utils.insertValueFromVarName(
        allocator,
        "full_word",
        MaybeRelocatable.fromInt(u8, if (n_bytes.cmp(&Felt252.fromInt(u32, 4)).compare(.gte))
            1
        else
            0),
        vm,
        ids_data,
        ap_tracking,
    );
}

/// Inner implementation of [`sha256_main_constant_input_length`] and [`sha256_main_arbitrary_input_length`]
fn sha256Main(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
    iv: *[8]u32,
) !void {
    const input_ptr = try hint_utils.getPtrFromVarName("sha256_start", vm, ids_data, ap_tracking);

    // The original code gets it from `ids` in both cases, and this makes it easier
    // to implement the arbitrary length one
    const input_chunk_size_felts =
        (try hint_utils.getConstantFromVarName("SHA256_INPUT_CHUNK_SIZE_FELTS", constants)).toInt(usize) catch 100;

    if (input_chunk_size_felts >= 100)
        return HintError.AssertionFailed;

    var message = try std.ArrayList(u8).initCapacity(allocator, 4 * input_chunk_size_felts);
    defer message.deinit();

    var buf: [4]u8 = undefined;

    for (0..input_chunk_size_felts) |i| {
        const input_element = try vm.getFelt(try input_ptr.addUint(i));

        const input_elem_u32 = (try feltToU32(input_element));

        std.mem.writeInt(u32, &buf, input_elem_u32, .big);

        try message.appendSlice(&buf);
    }

    const blocks: []const [64]u8 = &.{
        message.items[0..64].*,
    };

    sha256.compress(iv, blocks);

    var output = try std.ArrayList(MaybeRelocatable).initCapacity(allocator, iv.len);
    defer output.deinit();

    for (iv.*) |new_state| {
        try output.append(MaybeRelocatable.fromInt(u32, new_state));
    }

    const output_base = try hint_utils.getPtrFromVarName("output", vm, ids_data, ap_tracking);

    _ = try vm.segments.writeArg(std.ArrayList(MaybeRelocatable), output_base, &output);
}

// Implements hint:
// from starkware.cairo.common.cairo_sha256.sha256_utils import (
//     IV, compute_message_schedule, sha2_compress_function)

// _sha256_input_chunk_size_felts = int(ids.SHA256_INPUT_CHUNK_SIZE_FELTS)
// assert 0 <= _sha256_input_chunk_size_felts < 100

// w = compute_message_schedule(memory.get_range(
//     ids.sha256_start, _sha256_input_chunk_size_felts))
// new_state = sha2_compress_function(IV, w)
// segments.write_arg(ids.output, new_state)
pub fn sha256MainConstantInputLength(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    var iv = IV;
    try sha256Main(allocator, vm, ids_data, ap_tracking, constants, &iv);
}

// Implements hint:
// from starkware.cairo.common.cairo_sha256.sha256_utils import (
//     compute_message_schedule, sha2_compress_function)

// _sha256_input_chunk_size_felts = int(ids.SHA256_INPUT_CHUNK_SIZE_FELTS)
// assert 0 <= _sha256_input_chunk_size_felts < 100
// _sha256_state_size_felts = int(ids.SHA256_STATE_SIZE_FELTS)
// assert 0 <= _sha256_state_size_felts < 100
// w = compute_message_schedule(memory.get_range(
//     ids.sha256_start, _sha256_input_chunk_size_felts))
// new_state = sha2_compress_function(memory.get_range(ids.state, _sha256_state_size_felts), w)
// segments.write_arg(ids.output, new_state)
pub fn sha256MainArbitraryInputLength(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const iv_ptr = try hint_utils.getPtrFromVarName("state", vm, ids_data, ap_tracking);

    const state_size_felt =
        try hint_utils.getConstantFromVarName("SHA256_STATE_SIZE_FELTS", constants);

    const state_size = blk: {
        const size = state_size_felt.toInt(usize) catch return HintError.AssertionFailed;
        if (size == SHA256_STATE_SIZE_FELTS) break :blk size;
        if (size < 100) return HintError.InvalidValue;
        return HintError.AssertionFailed;
    };

    var iv_felt = try vm
        .getFeltRange(iv_ptr, state_size);
    defer iv_felt.deinit();

    var iv = try std.ArrayList(u32).initCapacity(allocator, iv_felt.items.len);
    defer iv.deinit();

    for (iv_felt.items) |x| try iv.append(try feltToU32(x));

    try sha256Main(allocator, vm, ids_data, ap_tracking, constants, iv.items[0..8]);
}

pub fn sha256Finalize(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const message = [_]u8{0} ** 64;

    var iv = IV;

    var iv_static = try std.ArrayList(MaybeRelocatable).initCapacity(allocator, iv.len);
    defer iv_static.deinit();

    for (iv) |n| try iv_static.append(MaybeRelocatable.fromInt(u32, n));

    const blocks: []const [64]u8 = &.{message[0..64].*};

    sha256.compress(&iv, blocks);

    var output = try std.ArrayList(MaybeRelocatable).initCapacity(allocator, SHA256_STATE_SIZE_FELTS);
    defer output.deinit();

    for (iv) |new_state| {
        try output.append(MaybeRelocatable.fromInt(u32, new_state));
    }

    const sha256_ptr_end = try hint_utils.getPtrFromVarName("sha256_ptr_end", vm, ids_data, ap_tracking);

    var padding = std.ArrayList(MaybeRelocatable).init(allocator);
    defer padding.deinit();

    var zero_vector_message = [_]MaybeRelocatable{MaybeRelocatable.fromInt(u8, 0)} ** 16;

    for (BLOCK_SIZE - 1) |_| {
        try padding.appendSlice(&zero_vector_message);
        try padding.appendSlice(iv_static.items);
        try padding.appendSlice(output.items);
    }

    _ = try vm.segments.writeArg(std.ArrayList(MaybeRelocatable), sha256_ptr_end, &padding);
}

const SHA256_INPUT_CHUNK_SIZE_FELTS: usize = 16;

test "Sha256Utils: sha256 input one" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{7} },
    });

    vm.run_context.fp = 2;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "full_word", "n_bytes",
    });
    defer ids_data.deinit();

    try sha256Input(std.testing.allocator, &vm, ids_data, .{});

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 0 }, .{1} },
    });
}

test "Sha256Utils: sha256 input zero" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 1 }, .{3} },
    });

    vm.run_context.fp = 2;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "full_word", "n_bytes",
    });
    defer ids_data.deinit();

    try sha256Input(std.testing.allocator, &vm, ids_data, .{});

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 0 }, .{0} },
    });
}

test "Sha256Utils: constant input length ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{ 3, 0 } },
        .{ .{ 2, 0 }, .{22} },
        .{ .{ 2, 1 }, .{22} },
        .{ .{ 2, 2 }, .{22} },
        .{ .{ 2, 3 }, .{22} },
        .{ .{ 2, 4 }, .{22} },
        .{ .{ 2, 5 }, .{22} },
        .{ .{ 2, 6 }, .{22} },
        .{ .{ 2, 7 }, .{22} },
        .{ .{ 2, 8 }, .{22} },
        .{ .{ 2, 9 }, .{22} },
        .{ .{ 2, 10 }, .{22} },
        .{ .{ 2, 11 }, .{22} },
        .{ .{ 2, 12 }, .{22} },
        .{ .{ 2, 13 }, .{22} },
        .{ .{ 2, 14 }, .{22} },
        .{ .{ 2, 15 }, .{22} },
        .{ .{ 3, 9 }, .{0} },
    });

    vm.run_context.fp = 2;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "sha256_start", "output",
    });
    defer ids_data.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try constants.put("SHA256_INPUT_CHUNK_SIZE_FELTS", Felt252.fromInt(usize, SHA256_INPUT_CHUNK_SIZE_FELTS));

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.SHA256_MAIN_CONSTANT_INPUT_LENGTH, &constants, &exec_scopes);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 3, 0 }, .{3704205499} },
        .{ .{ 3, 1 }, .{2308112482} },
        .{ .{ 3, 2 }, .{3022351583} },
        .{ .{ 3, 3 }, .{174314172} },
        .{ .{ 3, 4 }, .{1762869695} },
        .{ .{ 3, 5 }, .{1649521060} },
        .{ .{ 3, 6 }, .{2811202336} },
        .{ .{ 3, 7 }, .{4231099170} },
    });
}

test "Sha256Utils: arbitary input length ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{ 3, 0 } },
        .{ .{ 1, 2 }, .{ 4, 0 } },
        .{ .{ 2, 0 }, .{22} },
        .{ .{ 2, 1 }, .{22} },
        .{ .{ 2, 2 }, .{22} },
        .{ .{ 2, 3 }, .{22} },
        .{ .{ 2, 4 }, .{22} },
        .{ .{ 2, 5 }, .{22} },
        .{ .{ 2, 6 }, .{22} },
        .{ .{ 2, 7 }, .{22} },
        .{ .{ 2, 8 }, .{22} },
        .{ .{ 2, 9 }, .{22} },
        .{ .{ 2, 10 }, .{22} },
        .{ .{ 2, 11 }, .{22} },
        .{ .{ 2, 12 }, .{22} },
        .{ .{ 2, 13 }, .{22} },
        .{ .{ 2, 14 }, .{22} },
        .{ .{ 2, 15 }, .{22} },
        .{ .{ 3, 9 }, .{0} },
        .{ .{ 4, 0 }, .{0x6A09E667} },
        .{ .{ 4, 1 }, .{0xBB67AE85} },
        .{ .{ 4, 2 }, .{0x3C6EF372} },
        .{ .{ 4, 3 }, .{0xA54FF53A} },
        .{ .{ 4, 4 }, .{0x510E527F} },
        .{ .{ 4, 5 }, .{0x9B05688C} },
        .{ .{ 4, 6 }, .{0x1F83D9AB} },
        .{ .{ 4, 7 }, .{0x5BE0CD18} },
    });

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "sha256_start", "output", "state",
    });
    defer ids_data.deinit();

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try constants.put("SHA256_INPUT_CHUNK_SIZE_FELTS", Felt252.fromInt(usize, SHA256_INPUT_CHUNK_SIZE_FELTS));
    try constants.put("SHA256_STATE_SIZE_FELTS", Felt252.fromInt(usize, SHA256_STATE_SIZE_FELTS));

    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.SHA256_MAIN_ARBITRARY_INPUT_LENGTH, &constants, &exec_scopes);

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 3, 0 }, .{1676947577} },
        .{ .{ 3, 1 }, .{1555161467} },
        .{ .{ 3, 2 }, .{2679819371} },
        .{ .{ 3, 3 }, .{2084775296} },
        .{ .{ 3, 4 }, .{3059346845} },
        .{ .{ 3, 5 }, .{785647811} },
        .{ .{ 3, 6 }, .{2729325562} },
        .{ .{ 3, 7 }, .{2503090120} },
    });
}
