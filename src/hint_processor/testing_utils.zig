const std = @import("std");
const relocatable = @import("../vm/memory/relocatable.zig");

const CairoVM = @import("../vm/core.zig").CairoVM;

const Memory = @import("../vm/memory/memory.zig").Memory;
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;
const dict_manager_lib = @import("dict_manager.zig");
const IdsManager = @import("hint_utils.zig").IdsManager;
const HintReference = @import("../hint_processor/hint_processor_def.zig").HintReference;
const HintData = @import("../hint_processor/hint_processor_def.zig").HintData;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const Rc = @import("../vm/types/execution_scopes.zig").Rc;
const HintProccessor = @import("../hint_processor/hint_processor_def.zig").CairoVMHintProcessor;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

pub fn runHint(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    hint_code: []const u8,
    constants: *std.StringHashMap(Felt252),
    exec_scopes: *ExecutionScopes,
) !void {
    var hint_data = HintData{ .code = hint_code, .ids_data = ids_data, .ap_tracking = .{} };
    const hint_processor = HintProccessor{};
    try hint_processor.executeHint(allocator, vm, &hint_data, constants, exec_scopes);
}

pub fn initVMWithRangeCheck(allocator: std.mem.Allocator) !CairoVM {
    var vm = try CairoVM.init(allocator, .{});
    errdefer vm.deinit();

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    return vm;
}

pub fn checkMemory(mem: *Memory, comptime rows: anytype) !void {
    inline for (rows) |row| {
        try checkMemoryAddress(mem, row);
    }
}

pub fn checkMemoryAddress(mem: *Memory, data: anytype) !void {
    const expected = if (data[1].len == 2) MaybeRelocatable.fromRelocatable(Relocatable.init(data[1][0], data[1][1])) else MaybeRelocatable.fromInt(u256, data[1][0]);

    errdefer {
        std.log.err("failed expect: {any}, got: {any}\n", .{ expected, mem.get(Relocatable.init(data[0][0], data[0][1])) });
    }

    try std.testing.expectEqual(expected, mem.get(Relocatable.init(data[0][0], data[0][1])));
}

pub fn initDictManagerDefault(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes, tracker_num: i64, default: u64, data: []const struct { usize, usize }) !void {
    var tracker = try dict_manager_lib.DictTracker.initDefaultDict(allocator, relocatable.Relocatable.init(tracker_num, 0), MaybeRelocatable.fromInt(u64, default), null);
    errdefer tracker.deinit();

    for (data) |d| try tracker.insertValue(MaybeRelocatable.fromInt(usize, d[0]), MaybeRelocatable.fromInt(usize, d[1]));

    var dict_manager = try dict_manager_lib.DictManager.init(allocator);
    errdefer dict_manager.deinit();
    try dict_manager.trackers.put(2, tracker);

    try exec_scopes.assignOrUpdateVariable("dict_manager", .{ .dict_manager = try Rc(dict_manager_lib.DictManager).init(allocator, dict_manager) });
}

pub fn initDictManager(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes, tracker_num: i64, data: []const struct { usize, usize }) !void {
    var tracker = dict_manager_lib.DictTracker.initEmpty(allocator, relocatable.Relocatable.init(tracker_num, 0));
    errdefer tracker.deinit();

    for (data) |d| try tracker.insertValue(MaybeRelocatable.fromInt(usize, d[0]), MaybeRelocatable.fromInt(usize, d[1]));

    var dict_manager = try dict_manager_lib.DictManager.init(allocator);
    errdefer dict_manager.deinit();
    try dict_manager.trackers.put(2, tracker);

    try exec_scopes.assignOrUpdateVariable("dict_manager", .{ .dict_manager = try Rc(dict_manager_lib.DictManager).init(allocator, dict_manager) });
}

pub fn checkDictionary(exec_scopes: *ExecutionScopes, tracker_num: isize, data: []const struct { usize, usize }) !void {
    var dict_manager_rc = try exec_scopes.getDictManager();
    defer dict_manager_rc.releaseWithFn(dict_manager_lib.DictManager.deinit);

    var tracker = dict_manager_rc.value.trackers.get(tracker_num).?;

    for (data) |d| try std.testing.expectEqual(MaybeRelocatable.fromInt(usize, d[1]), try tracker.getValue(MaybeRelocatable.fromInt(usize, d[0])));
}

pub fn checkDictPtr(exec_scopes: *ExecutionScopes, tracker_num: isize, expected_ptr: relocatable.Relocatable) !void {
    const dict_manager_rc = try exec_scopes.getDictManager();
    defer dict_manager_rc.releaseWithFn(dict_manager_lib.DictManager.deinit);
    try std.testing.expectEqual(expected_ptr, dict_manager_rc.value.trackers.get(tracker_num).?.current_ptr);
}

pub fn setupIdsNonContinuousIdsData(allocator: std.mem.Allocator, data: []const struct { []const u8, i32 }) !std.StringHashMap(HintReference) {
    var ids_data = std.StringHashMap(HintReference).init(allocator);
    errdefer ids_data.deinit();

    for (data) |d| {
        try ids_data.put(d[0], HintReference.initSimple(d[1]));
    }

    return ids_data;
}

pub fn setupIdsForTestWithoutMemory(allocator: std.mem.Allocator, data: []const []const u8) !std.StringHashMap(HintReference) {
    var result = std.StringHashMap(HintReference).init(allocator);
    errdefer result.deinit();

    for (data, 0..) |name, idx| {
        try result.put(name, HintReference.initSimple(@as(i32, @intCast(idx)) - @as(i32, @intCast(data.len))));
    }

    return result;
}

pub fn setupIdsForTest(allocator: std.mem.Allocator, data: []const struct { name: []const u8, elems: []const ?MaybeRelocatable }, vm: *CairoVM) !std.StringHashMap(HintReference) {
    var result = std.StringHashMap(HintReference).init(allocator);
    errdefer result.deinit();

    var current_offset: usize = 0;
    var base_addr = vm.run_context.getFP();
    _ = try vm.addMemorySegment();

    for (data) |d| {
        try result.put(d.name, .{
            .dereference = true,
            .offset1 = .{
                .reference = .{ .FP, @intCast(current_offset), false },
            },
        });
        // update current offset
        current_offset = current_offset + d.elems.len;

        // Insert ids variables
        for (d.elems, 0..) |elem, n| {
            if (elem) |val| {
                try vm.insertInMemory(
                    allocator,
                    try base_addr.addUint(n),
                    val,
                );
            }
        }

        // Update base_addr
        base_addr.offset = base_addr.offset + d.elems.len;
    }

    return result;
}
