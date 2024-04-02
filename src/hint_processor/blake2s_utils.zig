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
const Allocator = std.mem.Allocator;
const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;
const MemoryError = @import("../vm/error.zig").MemoryError;
const blake2s_hash = @import("blake2s_hash.zig");
fn feltToU32(felt: Felt252) MathError!u32 {
    const u256_val = felt.toInteger();
    if (u256_val > 0xFFFFFFFF) {
        return MathError.Felt252ToU32Conversion;
    }
    return @intCast(u256_val);
}

fn getFixedSizeU32Array(comptime N: usize, h_range: std.ArrayList(Felt252)) ![N]u32 {
    var result: [N]u32 = undefined;
    for (h_range.items, 0..N) |h, i| {
        result[i] = try feltToU32(h);
    }
    return result;
}
fn getMaybeRelocArrayFromU32Array(allocator: Allocator, h_range: std.ArrayList(u32)) !std.ArrayList(MaybeRelocatable) {
    var result = std.ArrayList(MaybeRelocatable).init(allocator);
    for (h_range.items) |h| {
        const felt = Felt252.fromInt(u32, h);
        try result.append(MaybeRelocatable.fromFelt(felt));
    }
    return result;
}
fn computeBlake2sFunc(allocator: Allocator, vm: *CairoVM, output_ptr: Relocatable) !void {
    const h_felt_range = try vm.getFeltRange(try output_ptr.subUint(26), 8);
    defer h_felt_range.deinit();
    const h = try getFixedSizeU32Array(8, h_felt_range);

    const message_felt_range = try vm.getFeltRange(try output_ptr.subUint(18), 16);
    defer message_felt_range.deinit();
    const message = try getFixedSizeU32Array(16, message_felt_range);

    const t = try feltToU32(try vm.getFelt(try output_ptr.subUint(2)));
    const f = try feltToU32(try vm.getFelt(try output_ptr.subUint(1)));

    const h_range = try blake2s_hash.blake2s_compress(allocator, h, message, t, 9, f, 0);
    defer h_range.deinit();
    var new_state = try getMaybeRelocArrayFromU32Array(allocator, h_range);
    defer new_state.deinit();
    _ = try vm.loadData(output_ptr, &new_state);
}

// Implements hint:
//   from starkware.cairo.common.cairo_blake2s.blake2s_utils import compute_blake2s_func
//   compute_blake2s_func(segments=segments, output_ptr=ids.output)
//
pub fn blake2sCompute(allocator: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const output = try hint_utils.getPtrFromVarName("output", vm, ids_data, ap_tracking);
    try computeBlake2sFunc(allocator, vm, output);
}

// /* Implements Hint:
//     # Add dummy pairs of input and output.
//     from starkware.cairo.common.cairo_blake2s.blake2s_utils import IV, blake2s_compress

// _n_packed_instances = int(ids.N_PACKED_INSTANCES)
// assert 0 <= _n_packed_instances < 20
// _blake2s_input_chunk_size_felts = int(ids.INPUT_BLOCK_FELTS)
// assert 0 <= _blake2s_input_chunk_size_felts < 100

// message = [0] * _blake2s_input_chunk_size_felts
// modified_iv = [IV[0] ^ 0x01010020] + IV[1:]
// output = blake2s_compress(
//     message=message,
//     h=modified_iv,
//     t0=0,
//     t1=0,
//     f0=0xffffffff,
//     f1=0,
// )
// padding = (modified_iv + message + [0, 0xffffffff] + output) * (_n_packed_instances - 1)
// segments.write_arg(ids.blake2s_ptr_end, padding)

pub fn blake2sFinalize(allocator: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const N_PACKED_INSTANCES = 7;
    const blake2s_ptr_end = try hint_utils.getPtrFromVarName("blake2s_ptr_end", vm, ids_data, ap_tracking);
    std.debug.print("blake2s_ptr_end: {}\n", .{blake2s_ptr_end});
    const message: [16]u32 = .{0} ** 16;
    var modified_iv = blake2s_hash.IV;
    modified_iv[0] = blake2s_hash.IV[0] ^ 0x01010020;
    const output = try blake2s_hash.blake2s_compress(allocator, modified_iv, message, 0, 0, 0xffffffff, 0);
    defer output.deinit();
    var full_padding = std.ArrayList(u32).init(allocator);
    defer full_padding.deinit();
    for (N_PACKED_INSTANCES - 1) |_| {
        try full_padding.appendSlice(&modified_iv);
        try full_padding.appendSlice(&message);
        try full_padding.appendSlice(&.{ 0, 0xffffffff });
        try full_padding.appendSlice(output.items);
    }
    var data = try getMaybeRelocArrayFromU32Array(allocator, full_padding);
    defer data.deinit();
    _ = try vm.loadData(blake2s_ptr_end, &data);
}
test "compute blake2s output offset zero" {
    const hint_code = "from starkware.cairo.common.cairo_blake2s.blake2s_utils import compute_blake2s_func\ncompute_blake2s_func(segments=segments, output_ptr=ids.output)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 4;
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 26 } },
    });
    _ = try vm.segments.addSegment();
    const output = try vm.segments.addSegment();
    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "output",
            .elems = &.{MaybeRelocatable.fromRelocatable(output)},
        },
    }, &vm);

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();
    //Execute the hint

    const err = hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    try std.testing.expectError(MathError.RelocatableSubUsizeNegOffset, err);
}

test "compute blake2s output empty segment" {
    const hint_code = "from starkware.cairo.common.cairo_blake2s.blake2s_utils import compute_blake2s_func\ncompute_blake2s_func(segments=segments, output_ptr=ids.output)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 1;

    _ = try vm.addMemorySegment();
    const output = try vm.segments.addSegment();
    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "output",
            .elems = &.{MaybeRelocatable.fromRelocatable(try output.addInt(26))},
        },
    }, &vm);

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();
    //Execute the hint

    const err = hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    try std.testing.expectError(MemoryError.UnknownMemoryCell, err);
}

test "compute blake2s output not relocatable" {
    const hint_code = "from starkware.cairo.common.cairo_blake2s.blake2s_utils import compute_blake2s_func\ncompute_blake2s_func(segments=segments, output_ptr=ids.output)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 1;

    _ = try vm.addMemorySegment();
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"output"});

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();
    //Execute the hint

    const err = hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
    try std.testing.expectError(HintError.IdentifierNotRelocatable, err);
}

test "compute blake2s output input bigger than u32" {
    const hint_code = "from starkware.cairo.common.cairo_blake2s.blake2s_utils import compute_blake2s_func\ncompute_blake2s_func(segments=segments, output_ptr=ids.output)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 1;

    _ = try vm.segments.addSegment();
    var output = try vm.segments.addTempSegment();

    const data = [26]MaybeRelocatable{ MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959) };
    output = try vm.segments.loadData(std.testing.allocator, output, &data);
    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "output",
            .elems = &.{MaybeRelocatable.fromRelocatable(output)},
        },
    }, &vm);

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();
    //Execute the hint

    try std.testing.expectError(MathError.Felt252ToU32Conversion, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}

test "compute blake2s output input relocatable" {
    const hint_code = "from starkware.cairo.common.cairo_blake2s.blake2s_utils import compute_blake2s_func\ncompute_blake2s_func(segments=segments, output_ptr=ids.output)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 1;

    _ = try vm.segments.addSegment();
    var output = try vm.segments.addTempSegment();

    const data = [26]MaybeRelocatable{ MaybeRelocatable.fromRelocatable(Relocatable.init(5, 5)), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959), MaybeRelocatable.fromInt(u128, 7842562439562793675803603603688959) };
    output = try vm.segments.loadData(std.testing.allocator, output, &data);
    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "output",
            .elems = &.{MaybeRelocatable.fromRelocatable(output)},
        },
    }, &vm);

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();
    //Execute the hint

    try std.testing.expectError(MemoryError.ExpectedInteger, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined));
}

test "compute blake2s ok" {
    const hint_code = "from starkware.cairo.common.cairo_blake2s.blake2s_utils import compute_blake2s_func\ncompute_blake2s_func(segments=segments, output_ptr=ids.output)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 1;

    _ = try vm.segments.addSegment();
    var output = try vm.segments.addTempSegment();

    const data = [26]MaybeRelocatable{ MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17), MaybeRelocatable.fromInt(u128, 17) };
    output = try vm.segments.loadData(std.testing.allocator, output, &data);
    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "output",
            .elems = &.{MaybeRelocatable.fromRelocatable(output)},
        },
    }, &vm);

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();
    //Execute the hint
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);
}

test "finalize blake2s ok" {
    const hint_code = "# Add dummy pairs of input and output.\nfrom starkware.cairo.common.cairo_blake2s.blake2s_utils import IV, blake2s_compress\n\n_n_packed_instances = int(ids.N_PACKED_INSTANCES)\nassert 0 <= _n_packed_instances < 20\n_blake2s_input_chunk_size_felts = int(ids.INPUT_BLOCK_FELTS)\nassert 0 <= _blake2s_input_chunk_size_felts < 100\n\nmessage = [0] * _blake2s_input_chunk_size_felts\nmodified_iv = [IV[0] ^ 0x01010020] + IV[1:]\noutput = blake2s_compress(\n    message=message,\n    h=modified_iv,\n    t0=0,\n    t1=0,\n    f0=0xffffffff,\n    f1=0,\n)\npadding = (modified_iv + message + [0, 0xffffffff] + output) * (_n_packed_instances - 1)\nsegments.write_arg(ids.blake2s_ptr_end, padding)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    vm.run_context.fp.* = 1;

    // add segments
    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();

    const data = try vm.segments.addSegment();

    const ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "blake2s_ptr_end",
            .elems = &.{MaybeRelocatable.fromRelocatable(data)},
        },
    }, &vm);
    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();
    //Execute the hint
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const expected_data = [204]u32{
        1795745351, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,
        1541459225, 0,          0,          0,          0,          0,          0,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          0,          0,          4294967295, 813310313,  2491453561,
        3491828193, 2085238082, 1219908895, 514171180,  4245497115, 4193177630, 1795745351,
        3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635,  1541459225,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          0,          4294967295, 813310313,  2491453561, 3491828193,
        2085238082, 1219908895, 514171180,  4245497115, 4193177630, 1795745351, 3144134277,
        1013904242, 2773480762, 1359893119, 2600822924, 528734635,  1541459225, 0,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          4294967295, 813310313,  2491453561, 3491828193, 2085238082,
        1219908895, 514171180,  4245497115, 4193177630, 1795745351, 3144134277, 1013904242,
        2773480762, 1359893119, 2600822924, 528734635,  1541459225, 0,          0,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          0,          0,          0,          0,          0,
        0,          4294967295, 813310313,  2491453561, 3491828193, 2085238082, 1219908895,
        514171180,  4245497115, 4193177630, 1795745351, 3144134277, 1013904242, 2773480762,
        1359893119, 2600822924, 528734635,  1541459225, 0,          0,          0,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          0,          0,          0,          0,          0,
        4294967295, 813310313,  2491453561, 3491828193, 2085238082, 1219908895, 514171180,
        4245497115, 4193177630, 1795745351, 3144134277, 1013904242, 2773480762, 1359893119,
        2600822924, 528734635,  1541459225, 0,          0,          0,          0,
        0,          0,          0,          0,          0,          0,          0,
        0,          0,          0,          0,          0,          0,          4294967295,
        813310313,  2491453561, 3491828193, 2085238082, 1219908895, 514171180,  4245497115,
        4193177630,
    };

    const actual_data = try vm.segments.memory.getFeltRange(Relocatable.init(2, 0), 204);
    defer actual_data.deinit();
    const actual_data_u32 = try getFixedSizeU32Array(204, actual_data);
    try std.testing.expectEqualSlices(u32, &expected_data, &actual_data_u32);
}
