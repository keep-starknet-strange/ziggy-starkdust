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
    var new_state = try getMaybeRelocArrayFromU32Array(allocator, try blake2s_hash.blake2s_compress(allocator, h, message, t, 9, f, 0));
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
