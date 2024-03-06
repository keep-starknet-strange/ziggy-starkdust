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

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

pub fn usortEnterScope(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    var scope = std.StringHashMap(HintType).init(allocator);
    errdefer scope.deinit();

    if (exec_scopes.getFelt("usort_max_size")) |usort_max_size| {
        try scope.put("usort_max_size", .{ .felt = usort_max_size });
    } else |_| {}

    try exec_scopes.enterScope(scope);
}

fn orderFelt252(lhs: Felt252, rhs: Felt252) std.math.Order {
    return lhs.cmp(rhs);
}

/// improved binarysearch, return .found enum if found with index
/// returns .not_found if element not found and pos for insert
/// `items` must be sorted in ascending order with respect to `compareFn`.
///
/// O(log n) complexity.
pub fn binarySearch(
    comptime T: type,
    key: anytype,
    items: []const T,
    comptime compareFn: fn (key: @TypeOf(key), mid_item: T) std.math.Order,
) union(enum) {
    found: usize,
    not_found: usize,
} {
    var left: usize = 0;
    var right: usize = items.len;

    while (left < right) {
        // Avoid overflowing in the midpoint calculation
        const mid = left + (right - left) / 2;
        // Compare the key with the midpoint element
        switch (compareFn(key, items[mid])) {
            .eq => return .{ .found = mid },
            .gt => left = mid + 1,
            .lt => right = mid,
        }
    }

    std.debug.assert(left <= items.len);

    return .{
        .not_found = left,
    };
}

pub fn usortBody(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const input_ptr = try hint_utils.getPtrFromVarName("input", vm, ids_data, ap_tracking);
    const input_len = try hint_utils.getIntegerFromVarName("input_len", vm, ids_data, ap_tracking);
    const input_len_u64 = input_len.intoU64() catch return HintError.BigintToUsizeFail;

    if (exec_scopes.getValue(.u64, "usort_max_size")) |usort_max_size| {
        if (input_len_u64 > usort_max_size) return HintError.UsortOutOfRange;
    } else |_| {}

    var positions_dict = std.AutoHashMap(Felt252, std.ArrayList(u64)).init(allocator);
    defer positions_dict.deinit();
    defer {
        var it = positions_dict.valueIterator();
        while (it.next()) |v| {
            v.deinit();
        }
    }

    var output = std.ArrayList(Felt252).init(allocator);
    defer output.deinit();

    for (0..input_len_u64) |i| {
        const val = try vm.getFelt(try input_ptr.addUint(i));
        switch (binarySearch(Felt252, val, output.items, orderFelt252)) {
            .not_found => |output_index| try output.insert(output_index, val),
            else => {},
        }

        var entry = positions_dict.getPtr(val) orelse
            @constCast(&std.ArrayList(u64).init(allocator));

        try entry.append(i);
    }

    var multiplicities = std.ArrayList(usize).init(allocator);
    defer multiplicities.deinit();

    for (output.items) |k| {
        try multiplicities.append(positions_dict.get(k).?.items.len);
    }

    try exec_scopes.assignOrUpdateVariable("positions_dict", .{ .felt_map_of_u64_list = positions_dict });
    const output_base = try vm.addMemorySegment();
    const multiplicities_base = try vm.addMemorySegment();
    const output_len = output.items.len;

    for (0.., output.items) |i, sorted_element| {
        try vm.insertInMemory(allocator, try output_base.addUint(i), MaybeRelocatable.fromFelt(sorted_element));
    }

    for (0.., multiplicities.items) |i, repetition_amount| {
        try vm.insertInMemory(allocator, try multiplicities_base.addUint(i), MaybeRelocatable.fromInt(usize, repetition_amount));
    }

    try hint_utils.insertValueFromVarName(
        allocator,
        "output_len",
        MaybeRelocatable.fromInt(usize, output_len),
        vm,
        ids_data,
        ap_tracking,
    );
    try hint_utils.insertValueFromVarName(
        allocator,
        "output",
        MaybeRelocatable.fromRelocatable(output_base),
        vm,
        ids_data,
        ap_tracking,
    );
    try hint_utils.insertValueFromVarName(
        allocator,
        "multiplicities",
        MaybeRelocatable.fromRelocatable(multiplicities_base),
        vm,
        ids_data,
        ap_tracking,
    );
}

pub fn verifyUsort(
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const value = try hint_utils.getIntegerFromVarName("value", vm, ids_data, ap_tracking);
    var positions = ((try exec_scopes.getValueRef(.felt_map_of_u64_list, "positions_dict")).fetchRemove(value) orelse return HintError.UnexpectedPositionsDictFail).value;

    // reverse array
    var tmp: u64 = 0;
    for (0..positions.items.len / 2) |i| {
        tmp = positions.items[i];
        positions.items[i] = positions.items[positions.items.len - 1 - i];
        positions.items[positions.items.len - 1 - i] = tmp;
    }

    try exec_scopes.assignOrUpdateVariable("positions", .{ .u64_list = positions });
    try exec_scopes.assignOrUpdateVariable("last_pos", .{ .felt = Felt252.zero() });
}

pub fn verifyMultiplicityAssert(exec_scopes: *ExecutionScopes) !void {
    const positions_len = (try exec_scopes.getValueRef(.u64_list, "positions")).items.len;

    if (positions_len != 0) return HintError.PositionsLengthNotZero;
}

pub fn verifyMultiplicityBody(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const current_pos = (try exec_scopes
        .getValueRef(.u64_list, "positions")).popOrNull() orelse return HintError.CouldntPopPositions;

    const pos_diff = Felt252.fromInt(u64, current_pos).sub(try exec_scopes.getFelt("last_pos"));
    try hint_utils.insertValueFromVarName(allocator, "next_item_index", MaybeRelocatable.fromFelt(pos_diff), vm, ids_data, ap_tracking);

    try exec_scopes.assignOrUpdateVariable("last_pos", .{ .felt = Felt252.fromInt(u64, current_pos + 1) });
}

test "Usort: usort with max size" {
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("usort_max_size", .{ .u64 = 1 });

    try usortEnterScope(std.testing.allocator, &exec_scopes);

    try std.testing.expectEqual(Felt252.one(), try exec_scopes.getFelt("usort_max_size"));
}

test "Usort: usort out of range" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });
    //Initialize fp
    vm.run_context.fp.* = Relocatable.init(1, 2);
    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsForTestWithoutMemory(
        std.testing.allocator,
        &.{
            "input",
            "input_len",
        },
    );
    defer ids_data.deinit();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 1 } },
        .{ .{ 1, 1 }, .{5} },
    });
    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.USORT_BODY, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("usort_max_size", .{ .u64 = 1 });

    try std.testing.expectError(HintError.UsortOutOfRange, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "Usort: usortVerify ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    var positions_dict = std.AutoHashMap(Felt252, std.ArrayList(u64)).init(std.testing.allocator);

    var arr2 = std.ArrayList(u64).init(std.testing.allocator);
    try arr2.append(2);
    var arr1 = std.ArrayList(u64).init(std.testing.allocator);
    try arr1.append(1);
    var arr0 = std.ArrayList(u64).init(std.testing.allocator);
    try arr0.append(0);

    try positions_dict.put(Felt252.zero(), arr2);
    try positions_dict.put(Felt252.one(), arr1);
    try positions_dict.put(Felt252.three(), arr0);

    try exec_scopes.assignOrUpdateVariable("positions_dict", .{ .felt_map_of_u64_list = positions_dict });

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });

    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsForTest(
        std.testing.allocator,
        &.{
            .{
                .name = "value",
                .elems = &.{
                    MaybeRelocatable.fromInt(u64, 0),
                },
            },
        },
        &vm,
    );
    defer ids_data.deinit();

    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.USORT_VERIFY, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqualSlices(u64, &.{2}, (try exec_scopes.getValueRef(.u64_list, "positions")).items);
    try std.testing.expectEqual(try exec_scopes.getFelt("last_pos"), Felt252.zero());
}

test "Usort: usortVerifyMultiplicityAssert ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });

    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsForTest(
        std.testing.allocator,
        &.{},
        &vm,
    );
    defer ids_data.deinit();

    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.USORT_VERIFY_MULTIPLICITY_ASSERT, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var positions = std.ArrayList(u64).init(std.testing.allocator);
    try positions.append(0);

    try exec_scopes.assignOrUpdateVariable("positions", .{ .u64_list = positions });

    try std.testing.expectError(HintError.PositionsLengthNotZero, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));

    _ = positions.pop();

    try exec_scopes.assignOrUpdateVariable("positions", .{ .u64_list = positions });

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
}

test "Usort: usortVerifyMultiplicityBody ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.segments.addSegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var positions = std.ArrayList(u64).init(std.testing.allocator);
    try positions.appendSlice(&.{ 1, 0, 4, 7, 10 });

    try exec_scopes.assignOrUpdateVariable("positions", .{ .u64_list = positions });
    try exec_scopes.assignOrUpdateVariable("last_pos", .{ .u64 = 3 });

    try vm.builtin_runners.append(.{
        .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true),
    });

    //Create hint_data
    var ids_data =
        try testing_utils.setupIdsForTest(
        std.testing.allocator,
        &.{
            .{
                .name = "next_item_index",
                .elems = &.{
                    null,
                },
            },
        },
        &vm,
    );
    defer ids_data.deinit();

    //Execute the hint
    const hint_processor = HintProcessor{};
    var hint_data = HintData.init(hint_codes.USORT_VERIFY_MULTIPLICITY_BODY, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqualSlices(
        u64,
        (try exec_scopes.getValueRef(.u64_list, "positions")).items,
        &.{ 1, 0, 4, 7 },
    );
    try std.testing.expectEqual(Felt252.fromInt(u8, 11), try exec_scopes.getFelt("last_pos"));

    try std.testing.expectEqual(Felt252.fromInt(u8, 7), hint_utils.getIntegerFromVarName("next_item_index", &vm, ids_data, .{}));
}
