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

// Implements hint: "memory[ap] = to_felt_or_relocatable(ids.n >= 10)"
pub fn nGreaterThan10(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const n = try hint_utils.getIntegerFromVarName("n", vm, ids_data, ap_tracking);
    var val = n.toInteger();
    if (val > std.math.maxInt(usize))
        val = 10;

    const v: usize = @intCast(val);

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(if (v >= 10) Felt252.one() else Felt252.zero()));
}

// Implements hint: "memory[ap] = to_felt_or_relocatable(ids.n >= 2)"
pub fn nGreaterThan2(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var n = (try hint_utils.getIntegerFromVarName("n", vm, ids_data, ap_tracking)).toInteger();

    if (n > std.math.maxInt(usize))
        n = 2;

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(if (n >= 2) Felt252.one() else Felt252.zero()));
}

test "PoseidonUtils: run nGreaterThan10 true" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{21} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n",
    });

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.NONDET_N_GREATER_THAN_10, ids_data, .{});

    vm.run_context.ap.* = Relocatable.init(1, 3);
    vm.run_context.fp.* = Relocatable.init(1, 1);

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.one(), try vm.segments.memory.getFelt(vm.run_context.getAP()));
}

test "PoseidonUtils: run nGreaterThan10 false" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{9} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n",
    });

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.NONDET_N_GREATER_THAN_10, ids_data, .{});

    vm.run_context.ap.* = Relocatable.init(1, 3);
    vm.run_context.fp.* = Relocatable.init(1, 1);

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.zero(), try vm.segments.memory.getFelt(vm.run_context.getAP()));
}

test "PoseidonUtils: run nGreaterThan2 true" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{9} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n",
    });

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.NONDET_N_GREATER_THAN_2, ids_data, .{});

    vm.run_context.ap.* = Relocatable.init(1, 3);
    vm.run_context.fp.* = Relocatable.init(1, 1);

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.one(), try vm.segments.memory.getFelt(vm.run_context.getAP()));
}

test "PoseidonUtils: run nGreaterThan2 false" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n",
    });

    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.NONDET_N_GREATER_THAN_2, ids_data, .{});

    vm.run_context.ap.* = Relocatable.init(1, 3);
    vm.run_context.fp.* = Relocatable.init(1, 1);

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.zero(), try vm.segments.memory.getFelt(vm.run_context.getAP()));
}
