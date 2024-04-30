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

const DictManager = @import("dict_manager.zig").DictManager;
const Rc = @import("../vm/types/execution_scopes.zig").Rc;
const DictTracker = @import("dict_manager.zig").DictTracker;

const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;
const MemoryError = @import("../vm/error.zig").MemoryError;

const DICT_ACCESS_SIZE = @import("dict_hint_utils.zig").DICT_ACCESS_SIZE;

const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

fn getAccessIndices(
    exec_scopes: *ExecutionScopes,
) !*std.AutoHashMap(Felt252, std.ArrayList(Felt252)) {
    return exec_scopes.getValueRef(std.AutoHashMap(Felt252, std.ArrayList(Felt252)), "access_indices") catch HintError.VariableNotInScopeError;
}

fn cmpByValue(_: void, a: Felt252, b: Felt252) bool {
    return a.lt(b);
}

fn reversedCmpByValue(_: void, a: Felt252, b: Felt252) bool {
    return a.gt(b);
}

// Implements hint:
//     current_access_indices = sorted(access_indices[key])[::-1]
//     current_access_index = current_access_indices.pop()
//     memory[ids.range_check_ptr] = current_access_index
pub fn squashDictInnerFirstIteration(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //Check that access_indices and key are in scope
    const key = try exec_scopes.getValue(Felt252, "key");
    const range_check_ptr = try hint_utils.getPtrFromVarName("range_check_ptr", vm, ids_data, ap_tracking);
    const access_indices = try getAccessIndices(exec_scopes);
    //Get current_indices from access_indices
    var current_access_indices = try (access_indices.get(key) orelse return HintError.NoKeyInAccessIndices).clone();
    errdefer current_access_indices.deinit();

    std.sort.block(Felt252, current_access_indices.items, {}, cmpByValue);

    {
        // reverse array
        var tmp: Felt252 = undefined;
        for (0..current_access_indices.items.len / 2) |i| {
            tmp = current_access_indices.items[i];
            current_access_indices.items[i] = current_access_indices.items[current_access_indices.items.len - 1 - i];
            current_access_indices.items[current_access_indices.items.len - 1 - i] = tmp;
        }
    }

    //Get current_access_index
    const first_val = current_access_indices.popOrNull() orelse return HintError.EmptyCurrentAccessIndices;
    //Store variables in scope

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_access_indices });
    try exec_scopes.assignOrUpdateVariable("current_access_index", .{ .felt = first_val });
    // //Insert current_accesss_index into range_check_ptr
    try vm.insertInMemory(allocator, range_check_ptr, MaybeRelocatable.fromFelt(first_val));
}

// Implements Hint: ids.should_skip_loop = 0 if current_access_indices else 1
pub fn squashDictInnerSkipLoop(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //Check that current_access_indices is in scope
    const current_access_indices = try exec_scopes.getValue(std.ArrayList(Felt252), "current_access_indices");
    //Main Logic
    const should_skip_loop = if (current_access_indices.items.len == 0)
        Felt252.one()
    else
        Felt252.zero();

    try hint_utils.insertValueFromVarName(
        allocator,
        "should_skip_loop",
        MaybeRelocatable.fromFelt(should_skip_loop),
        vm,
        ids_data,
        ap_tracking,
    );
}

// Implements Hint:
//    new_access_index = current_access_indices.pop()
//    ids.loop_temps.index_delta_minus1 = new_access_index - current_access_index - 1
//    current_access_index = new_access_index
pub fn squashDictInnerCheckAccessIndex(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //Check that current_access_indices and current_access_index are in scope
    const current_access_index = try exec_scopes.getValue(Felt252, "current_access_index");
    const current_access_indices =
        try exec_scopes.getValueRef(std.ArrayList(Felt252), "current_access_indices");
    //Main Logic
    const new_access_index = current_access_indices
        .popOrNull() orelse return HintError.EmptyCurrentAccessIndices;
    const index_delta_minus1 = new_access_index.sub(current_access_index).sub(Felt252.one());
    //loop_temps.delta_minus1 = loop_temps + 0 as it is the first field of the struct
    //Insert loop_temps.delta_minus1 into memory
    try hint_utils.insertValueFromVarName(allocator, "loop_temps", MaybeRelocatable.fromFelt(index_delta_minus1), vm, ids_data, ap_tracking);
    try exec_scopes.assignOrUpdateVariable("new_access_index", .{ .felt = new_access_index });
    try exec_scopes.assignOrUpdateVariable("current_access_index", .{ .felt = new_access_index });
}

// Implements Hint: ids.loop_temps.should_continue = 1 if current_access_indices else 0
pub fn squashDictInnerContinueLoop(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //Check that ids contains the reference id for each variable used by the hint
    //Get addr for ids variables
    const loop_temps_addr = try hint_utils.getRelocatableFromVarName("loop_temps", vm, ids_data, ap_tracking);
    //Check that current_access_indices is in scope
    const current_access_indices = try exec_scopes.getValue(std.ArrayList(Felt252), "current_access_indices");
    //Main Logic
    const should_continue = if (current_access_indices.items.len == 0)
        Felt252.zero()
    else
        Felt252.one();
    //loop_temps.delta_minus1 = loop_temps + 3 as it is the fourth field of the struct
    //Insert loop_temps.delta_minus1 into memory
    const should_continue_addr = try loop_temps_addr.addUint(3);
    try vm.insertInMemory(allocator, should_continue_addr, MaybeRelocatable.fromFelt(should_continue));
}

// Implements Hint: assert len(current_access_indices) == 0
pub fn squashDictInnerLenAssert(exec_scopes: *ExecutionScopes) !void {
    //Check that current_access_indices is in scope
    const current_access_indices = try exec_scopes.getValue(std.ArrayList(Felt252), "current_access_indices");
    if (current_access_indices.items.len != 0)
        return HintError.CurrentAccessIndicesNotEmpty;
}

//Implements hint: assert ids.n_used_accesses == len(access_indices[key]
pub fn squashDictInnerUsedAccessesAssert(
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const key = try exec_scopes.getValue(Felt252, "key");
    const n_used_accesses = try hint_utils.getIntegerFromVarName("n_used_accesses", vm, ids_data, ap_tracking);
    const access_indices = try getAccessIndices(exec_scopes);
    //Main Logic
    const access_indices_at_key = access_indices
        .get(key) orelse return HintError.NoKeyInAccessIndices;

    if (!n_used_accesses.equal(Felt252.fromInt(usize, access_indices_at_key.items.len)))
        return HintError.NumUsedAccessesAssertFail;
}

// Implements Hint: assert len(keys) == 0
pub fn squashDictInnerAssertLenKeys(
    exec_scopes: *ExecutionScopes,
) !void {
    //Check that current_access_indices is in scope
    const keys = try exec_scopes.getValue(std.ArrayList(Felt252), "keys");
    if (keys.items.len != 0)
        return HintError.KeysNotEmpty;
}

// Implements Hint:
//  assert len(keys) > 0, 'No keys left but remaining_accesses > 0.'
//  ids.next_key = key = keys.pop()
pub fn squashDictInnerNextKey(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //Check that current_access_indices is in scope
    var keys = try exec_scopes.getValueRef(std.ArrayList(Felt252), "keys");

    const next_key = keys.popOrNull() orelse return HintError.EmptyKeys;
    //Insert next_key into ids.next_keys
    try hint_utils.insertValueFromVarName(allocator, "next_key", MaybeRelocatable.fromFelt(next_key), vm, ids_data, ap_tracking);
    //Update local variables
    try exec_scopes.assignOrUpdateVariable("key", .{ .felt = next_key });
}

// Implements hint:
//     dict_access_size = ids.DictAccess.SIZE
//     address = ids.dict_accesses.address_
//     assert ids.ptr_diff % dict_access_size == 0, \
//         'Accesses array size must be divisible by DictAccess.SIZE'
//     n_accesses = ids.n_accesses
//     if '__squash_dict_max_size' in globals():
//         assert n_accesses <= __squash_dict_max_size, \
//             f'squash_dict() can only be used with n_accesses<={__squash_dict_max_size}. ' \
//             f'Got: n_accesses={n_accesses}.'
//     # A map from key to the list of indices accessing it.
//     access_indices = {}
//     for i in range(n_accesses):
//         key = memory[address + dict_access_size * i]
//         access_indices.setdefault(key, []).append(i)
//     # Descending list of keys.
//     keys = sorted(access_indices.keys(), reverse=True)
//     # Are the keys used bigger than range_check bound.
//     ids.big_keys = 1 if keys[0] >= range_check_builtin.bound else 0
//     ids.first_key = key = keys.pop()
pub fn squashDict(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //Get necessary variables addresses from ids
    const address = try hint_utils.getPtrFromVarName("dict_accesses", vm, ids_data, ap_tracking);
    const ptr_diff = (try hint_utils.getIntegerFromVarName("ptr_diff", vm, ids_data, ap_tracking)).intoUsize() catch return HintError.PtrDiffNotDivisibleByDictAccessSize;
    const n_accesses = try hint_utils.getIntegerFromVarName("n_accesses", vm, ids_data, ap_tracking);
    //Get range_check_builtin
    const range_check_builtin = try vm.getRangeCheckBuiltin();
    const range_check_bound = range_check_builtin.bound.?;

    //Main Logic
    if (ptr_diff % DICT_ACCESS_SIZE != 0)
        return HintError.PtrDiffNotDivisibleByDictAccessSize;

    if (exec_scopes.getValue(Felt252, "__squash_dict_max_size")) |max_size| {
        if (n_accesses.gt(max_size))
            return HintError.SquashDictMaxSizeExceeded;
    } else |_| {}

    const n_accesses_usize = n_accesses
        .intoUsize() catch return HintError.NAccessesTooBig;

    //A map from key to the list of indices accessing it.
    var access_indices = std.AutoHashMap(Felt252, std.ArrayList(Felt252)).init(allocator);

    for (0..n_accesses_usize) |i| {
        const key_addr = try address.addUint(DICT_ACCESS_SIZE * i);
        const key = vm
            .getFelt(key_addr) catch return MemoryError.ExpectedInteger;

        var arr =
            access_indices.getPtr(key) orelse blk: {
            const data = std.ArrayList(Felt252).init(allocator);
            errdefer data.deinit();
            try access_indices.put(key, data);
            break :blk access_indices.getPtr(key).?;
        };

        try arr.append(Felt252.fromInt(usize, i));
    }

    //Descending list of keys.
    var keys = std.ArrayList(Felt252).init(allocator);
    var it = access_indices.keyIterator();

    while (it.next()) |v| {
        try keys.append(v.*);
    }

    std.sort.block(Felt252, keys.items, {}, reversedCmpByValue);

    //Are the keys used bigger than the range_check bound.
    const big_keys = if (keys.items[0].ge(range_check_bound))
        Felt252.one()
    else
        Felt252.zero();

    try hint_utils.insertValueFromVarName(allocator, "big_keys", MaybeRelocatable.fromFelt(big_keys), vm, ids_data, ap_tracking);
    const key = keys.popOrNull() orelse return HintError.EmptyKeys;

    try hint_utils.insertValueFromVarName(allocator, "first_key", MaybeRelocatable.fromFelt(key), vm, ids_data, ap_tracking);
    //Insert local variables into scope
    try exec_scopes.assignOrUpdateVariable("access_indices", .{ .felt_map_of_felt_list = access_indices });
    try exec_scopes.assignOrUpdateVariable("keys", .{ .felt_list = keys });
    try exec_scopes.assignOrUpdateVariable("key", .{ .felt = key });
}

test "SquashDictUtil: squashDictInnerFirstIteration valid" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_FIRST_ITERATION;
    //Prepare scope variables
    var access_indices = std.AutoHashMap(Felt252, std.ArrayList(Felt252)).init(std.testing.allocator);

    var current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    try current_accessed_indices.appendSlice(&.{
        Felt252.fromInt(u8, 9),
        Felt252.fromInt(u8, 3),
        Felt252.fromInt(u8, 10),
        Felt252.fromInt(u8, 7),
    });

    try access_indices.put(Felt252.fromInt(u8, 5), current_accessed_indices);
    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("access_indices", .{ .felt_map_of_felt_list = access_indices });
    try exec_scopes.assignOrUpdateVariable("key", .{ .felt = Felt252.fromInt(u8, 5) });

    //Initialize fp
    vm.run_context.fp = 1;
    //Insert ids into memory (range_check_ptr)
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.addMemorySegment();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "range_check_ptr",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
    //Check scope variables

    try std.testing.expectEqualSlices(Felt252, &.{
        Felt252.fromInt(u8, 10),
        Felt252.fromInt(u8, 9),
        Felt252.fromInt(u8, 7),
    }, (try exec_scopes.getValue(std.ArrayList(Felt252), "current_access_indices")).items);

    try std.testing.expectEqual(Felt252.fromInt(u8, 3), try exec_scopes.getValue(Felt252, "current_access_index"));
    //Check that current_access_index is now at range_check_ptr
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 2, 0 }, .{3} },
    });
}

test "SquashDictUtil: squashDictInnerFirstIteration no local variable" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_FIRST_ITERATION;
    //No scope variables
    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    //Initialize fp
    vm.run_context.fp = 1;
    //Insert ids into memory (range_check_ptr)
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
    });
    //Create ids_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "range_check_ptr",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var hint_data = HintData.init(hint_code, ids_data, .{});
    //Execute the hint
    const hint_processor = HintProcessor{};
    try std.testing.expectError(HintError.VariableNotInScopeError, hint_processor.executeHint(
        std.testing.allocator,
        &vm,
        &hint_data,
        undefined,
        &exec_scopes,
    ));
}

test "SquashDictUtil: squashDictInnerFirstIteration empty accessed indices" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_FIRST_ITERATION;
    //Prepare scope variables
    var access_indices = std.AutoHashMap(Felt252, std.ArrayList(Felt252)).init(std.testing.allocator);

    const current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    try access_indices.put(Felt252.fromInt(u8, 5), current_accessed_indices);
    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("access_indices", .{ .felt_map_of_felt_list = access_indices });
    try exec_scopes.assignOrUpdateVariable("key", .{ .felt = Felt252.fromInt(u8, 5) });

    //Initialize fp
    vm.run_context.fp = 1;
    //Insert ids into memory (range_check_ptr)
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
    });

    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.addMemorySegment();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "range_check_ptr",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.EmptyCurrentAccessIndices, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: should skip valid empty access indices" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_SKIP_LOOP;
    //Prepare scope variables

    const current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();
    //Initialize fp
    vm.run_context.fp = 1;

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "should_skip_loop",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    //Check that current_access_index is now at range_check_ptr
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 0 }, .{1} },
    });
}

test "SquashDictUtil: should skip valid non-empty access indices" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_SKIP_LOOP;
    //Prepare scope variables

    var current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);
    try current_accessed_indices.appendSlice(&.{
        Felt252.fromInt(u8, 4),
        Felt252.fromInt(u8, 7),
    });

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();
    //Initialize fp
    vm.run_context.fp = 1;

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "should_skip_loop",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    //Check that current_access_index is now at range_check_ptr
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 0 }, .{0} },
    });
}

test "SquashDictUtil: squashDictInnerCheckAccessIndex valid" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_CHECK_ACCESS_INDEX;
    //Prepare scope variables

    var current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    try current_accessed_indices.appendSlice(&.{
        Felt252.fromInt(u8, 10),
        Felt252.fromInt(u8, 9),
        Felt252.fromInt(u8, 7),
        Felt252.fromInt(u8, 5),
    });

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });
    try exec_scopes.assignOrUpdateVariable("current_access_index", .{ .felt = Felt252.fromInt(u8, 1) });

    //Initialize fp
    vm.run_context.fp = 1;
    //Insert ids into memory (range_check_ptr)

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "loop_temps",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
    //Check scope variables

    try std.testing.expectEqualSlices(Felt252, &.{
        Felt252.fromInt(u8, 10),
        Felt252.fromInt(u8, 9),
        Felt252.fromInt(u8, 7),
    }, (try exec_scopes.getValue(std.ArrayList(Felt252), "current_access_indices")).items);

    try std.testing.expectEqual(Felt252.fromInt(u8, 5), try exec_scopes.getValue(Felt252, "new_access_index"));
    try std.testing.expectEqual(Felt252.fromInt(u8, 5), try exec_scopes.getValue(Felt252, "current_access_index"));

    //Check that current_access_index is now at range_check_ptr
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 0 }, .{3} },
    });
}

test "SquashDictUtil: squashDictInnerCheckAccessIndex current addr empty" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_CHECK_ACCESS_INDEX;
    //Prepare scope variables

    const current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);
    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });
    try exec_scopes.assignOrUpdateVariable("current_access_index", .{ .felt = Felt252.fromInt(u8, 1) });

    //Initialize fp
    vm.run_context.fp = 1;
    //Insert ids into memory (range_check_ptr)
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
    });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "loop_temps",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.EmptyCurrentAccessIndices, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDictInnerContinueLoop non-empty current_access_indicies" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_CONTINUE_LOOP;
    //Prepare scope variables

    var current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    try current_accessed_indices.appendSlice(&.{
        Felt252.fromInt(u8, 4),
        Felt252.fromInt(u8, 7),
    });

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });

    //Initialize fp
    vm.run_context.fp = 1;
    //Insert ids into memory (range_check_ptr)

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "loop_temps",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
    //Check scope variables

    //Check that current_access_index is now at range_check_ptr
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{1} },
    });
}

test "SquashDictUtil: squashDictInnerContinueLoop empty current_access_indicies" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_CONTINUE_LOOP;
    //Prepare scope variables

    const current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });

    //Initialize fp
    vm.run_context.fp = 1;
    //Insert ids into memory (range_check_ptr)

    _ = try vm.addMemorySegment();
    _ = try vm.addMemorySegment();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "loop_temps",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
    //Check scope variables

    //Check that current_access_index is now at range_check_ptr
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{0} },
    });
}

test "SquashDictUtil: squashDictInnerAssertLen is empty" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_LEN_ASSERT;
    //Prepare scope variables

    const current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{});

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
}

test "SquashDictUtil: squashDictInnerAssertLen is not" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_LEN_ASSERT;
    //Prepare scope variables

    var current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    try current_accessed_indices.append(Felt252.fromInt(u16, 29));

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("current_access_indices", .{ .felt_list = current_accessed_indices });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{});

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.CurrentAccessIndicesNotEmpty, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDictInnerUsesAccessesAssert valid" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_USED_ACCESSES_ASSERT;
    //Prepare scope variables

    var access_indices = std.AutoHashMap(Felt252, std.ArrayList(Felt252)).init(std.testing.allocator);

    var current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    try current_accessed_indices.appendSlice(&.{
        Felt252.fromInt(u16, 9),
        Felt252.fromInt(u16, 3),
        Felt252.fromInt(u16, 10),
        Felt252.fromInt(u16, 7),
    });

    try access_indices.put(Felt252.fromInt(u8, 5), current_accessed_indices);

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 1;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{4} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("access_indices", .{ .felt_map_of_felt_list = access_indices });
    try exec_scopes.assignOrUpdateVariable("key", .{ .felt = Felt252.fromInt(u8, 5) });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n_used_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
}

test "SquashDictUtil: squashDictInnerUsesAccessesAssert number relocatable" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_USED_ACCESSES_ASSERT;
    //Prepare scope variables

    var access_indices = std.AutoHashMap(Felt252, std.ArrayList(Felt252)).init(std.testing.allocator);

    var current_accessed_indices = std.ArrayList(Felt252).init(std.testing.allocator);

    try current_accessed_indices.appendSlice(&.{
        Felt252.fromInt(u16, 9),
        Felt252.fromInt(u16, 3),
        Felt252.fromInt(u16, 10),
        Felt252.fromInt(u16, 7),
    });

    try access_indices.put(Felt252.fromInt(u8, 5), current_accessed_indices);

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    vm.run_context.fp = 1;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 1, 2 } },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("access_indices", .{ .felt_map_of_felt_list = access_indices });
    try exec_scopes.assignOrUpdateVariable("key", .{ .felt = Felt252.fromInt(u8, 5) });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "n_used_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.IdentifierNotInteger, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDictInnerAssertLenKeys not empty" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_ASSERT_LEN_KEYS;
    //Prepare scope variables

    var keys = std.ArrayList(Felt252).init(std.testing.allocator);
    try keys.append(Felt252.fromInt(u8, 3));

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("keys", .{ .felt_list = keys });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{});

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.KeysNotEmpty, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDictInnerAssertLenKeys empty" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_ASSERT_LEN_KEYS;
    //Prepare scope variables

    const keys = std.ArrayList(Felt252).init(std.testing.allocator);

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("keys", .{ .felt_list = keys });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{});

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
}

test "SquashDictUtil: squashDictInnerAssertLenKeys no keys" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_ASSERT_LEN_KEYS;
    //Prepare scope variables

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{});

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.VariableNotInScopeError, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDictInnerNextKey non-empty" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_NEXT_KEY;
    //Prepare scope variables

    var keys = std.ArrayList(Felt252).init(std.testing.allocator);

    try keys.appendSlice(&.{
        Felt252.fromInt(u16, 1),
        Felt252.fromInt(u16, 3),
    });

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();

    vm.run_context.fp = 1;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{3} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("keys", .{ .felt_list = keys });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "next_key",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    // check scopes
    try std.testing.expectEqualSlices(Felt252, &.{
        Felt252.fromInt(u8, 1),
    }, (try exec_scopes.getValue(std.ArrayList(Felt252), "keys")).items);

    try std.testing.expectEqual(Felt252.fromInt(u8, 3), try exec_scopes.getValue(Felt252, "key"));
}

test "SquashDictUtil: squashDictInnerNextKey key and keys empty" {
    const hint_code = hint_codes.SQUASH_DICT_INNER_NEXT_KEY;
    //Prepare scope variables

    const keys = std.ArrayList(Felt252).init(std.testing.allocator);

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();

    vm.run_context.fp = 1;

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("keys", .{ .felt_list = keys });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "next_key",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.EmptyKeys, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDict valid one key dict no max size" {
    //Dict = {1: (1,1), 1: (1,2)}
    const hint_code = hint_codes.SQUASH_DICT;

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    vm.run_context.fp = 5;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 3 }, .{6} },
        .{ .{ 1, 4 }, .{2} },
        .{ .{ 2, 0 }, .{1} },
        .{ .{ 2, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
        .{ .{ 2, 3 }, .{1} },
        .{ .{ 2, 4 }, .{1} },
        .{ .{ 2, 5 }, .{2} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses",
        "big_keys",
        "first_key",
        "ptr_diff",
        "n_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqualSlices(Felt252, &.{}, (try exec_scopes.getValue(std.ArrayList(Felt252), "keys")).items);
    try std.testing.expectEqual(Felt252.one(), try exec_scopes.getValue(Felt252, "key"));

    const access_indices = try exec_scopes.getValue(std.AutoHashMap(Felt252, std.ArrayList(Felt252)), "access_indices");
    try std.testing.expectEqual(1, access_indices.count());
    try std.testing.expectEqualSlices(Felt252, &.{ Felt252.zero(), Felt252.one() }, access_indices.get(Felt252.one()).?.items);

    //Check ids variables
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{1} },
    });
}

test "SquashDictUtil: squashDict valid two key dict no max size" {
    //Dict = {1: (1,1), 1: (1,2), 2: (10,10), 2: (10,20)}
    const hint_code = hint_codes.SQUASH_DICT;

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    vm.run_context.fp = 5;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 3 }, .{6} },
        .{ .{ 1, 4 }, .{4} },
        .{ .{ 2, 0 }, .{1} },
        .{ .{ 2, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
        .{ .{ 2, 3 }, .{1} },
        .{ .{ 2, 4 }, .{1} },
        .{ .{ 2, 5 }, .{2} },
        .{ .{ 2, 6 }, .{2} },
        .{ .{ 2, 7 }, .{10} },
        .{ .{ 2, 8 }, .{10} },
        .{ .{ 2, 9 }, .{2} },
        .{ .{ 2, 10 }, .{10} },
        .{ .{ 2, 11 }, .{20} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses",
        "big_keys",
        "first_key",
        "ptr_diff",
        "n_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqualSlices(Felt252, &.{Felt252.two()}, (try exec_scopes.getValue(std.ArrayList(Felt252), "keys")).items);
    try std.testing.expectEqual(Felt252.one(), try exec_scopes.getValue(Felt252, "key"));

    const access_indices = try exec_scopes.getValue(std.AutoHashMap(Felt252, std.ArrayList(Felt252)), "access_indices");
    try std.testing.expectEqual(2, access_indices.count());
    try std.testing.expectEqualSlices(Felt252, &.{ Felt252.zero(), Felt252.one() }, access_indices.get(Felt252.one()).?.items);
    try std.testing.expectEqualSlices(Felt252, &.{ Felt252.two(), Felt252.three() }, access_indices.get(Felt252.two()).?.items);

    //Check ids variables
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{1} },
    });
}

test "SquashDictUtil: squashDict one key with max size" {
    //Dict = {1: (1,1), 1: (1,2)}
    const hint_code = hint_codes.SQUASH_DICT;

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    vm.run_context.fp = 5;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 3 }, .{6} },
        .{ .{ 1, 4 }, .{2} },
        .{ .{ 2, 0 }, .{1} },
        .{ .{ 2, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
        .{ .{ 2, 3 }, .{1} },
        .{ .{ 2, 4 }, .{1} },
        .{ .{ 2, 5 }, .{2} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("__squash_dict_max_size", .{ .felt = Felt252.fromInt(u8, 12) });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses",
        "big_keys",
        "first_key",
        "ptr_diff",
        "n_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqualSlices(Felt252, &.{}, (try exec_scopes.getValue(std.ArrayList(Felt252), "keys")).items);
    try std.testing.expectEqual(Felt252.one(), try exec_scopes.getValue(Felt252, "key"));

    const access_indices = try exec_scopes.getValue(std.AutoHashMap(Felt252, std.ArrayList(Felt252)), "access_indices");
    try std.testing.expectEqual(1, access_indices.count());
    try std.testing.expectEqualSlices(Felt252, &.{ Felt252.zero(), Felt252.one() }, access_indices.get(Felt252.one()).?.items);

    //Check ids variables
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 1 }, .{0} },
        .{ .{ 1, 2 }, .{1} },
    });
}

test "SquashDictUtil: squashDict one key with max size exceeded" {
    //Dict = {1: (1,1), 1: (1,2)}
    const hint_code = hint_codes.SQUASH_DICT;

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    vm.run_context.fp = 5;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 3 }, .{6} },
        .{ .{ 1, 4 }, .{2} },
        .{ .{ 2, 0 }, .{1} },
        .{ .{ 2, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
        .{ .{ 2, 3 }, .{1} },
        .{ .{ 2, 4 }, .{1} },
        .{ .{ 2, 5 }, .{2} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("__squash_dict_max_size", .{ .felt = Felt252.fromInt(u8, 1) });

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses",
        "big_keys",
        "first_key",
        "ptr_diff",
        "n_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.SquashDictMaxSizeExceeded, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDict one key dict bad ptr diff" {
    //Dict = {1: (1,1), 1: (1,2)}
    const hint_code = hint_codes.SQUASH_DICT;

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    vm.run_context.fp = 5;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 3 }, .{7} },
        .{ .{ 1, 4 }, .{2} },
        .{ .{ 2, 0 }, .{1} },
        .{ .{ 2, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
        .{ .{ 2, 3 }, .{1} },
        .{ .{ 2, 4 }, .{1} },
        .{ .{ 2, 5 }, .{2} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses",
        "big_keys",
        "first_key",
        "ptr_diff",
        "n_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.PtrDiffNotDivisibleByDictAccessSize, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDict one key dict with n access too big" {
    //Dict = {1: (1,1), 1: (1,2)}
    const hint_code = hint_codes.SQUASH_DICT;

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    vm.run_context.fp = 5;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 3 }, .{6} },
        .{ .{ 1, 4 }, .{3618502761706184546546682988428055018603476541694452277432519575032261771265} },
        .{ .{ 2, 0 }, .{1} },
        .{ .{ 2, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
        .{ .{ 2, 3 }, .{1} },
        .{ .{ 2, 4 }, .{1} },
        .{ .{ 2, 5 }, .{2} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses",
        "big_keys",
        "first_key",
        "ptr_diff",
        "n_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try std.testing.expectError(HintError.NAccessesTooBig, hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "SquashDictUtil: squashDict one key dict no max size big keys" {
    //Dict = {1: (1,1), 1: (1,2)}
    const hint_code = hint_codes.SQUASH_DICT;

    //Create vm
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner{} });

    vm.run_context.fp = 5;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 3 }, .{6} },
        .{ .{ 1, 4 }, .{2} },
        .{ .{ 2, 0 }, .{3618502761706184546546682988428055018603476541694452277432519575032261771265} },
        .{ .{ 2, 1 }, .{1} },
        .{ .{ 2, 2 }, .{1} },
        .{ .{ 2, 3 }, .{3618502761706184546546682988428055018603476541694452277432519575032261771265} },
        .{ .{ 2, 4 }, .{1} },
        .{ .{ 2, 5 }, .{2} },
    });

    //Store scope variables
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create ids_data
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses",
        "big_keys",
        "first_key",
        "ptr_diff",
        "n_accesses",
    });

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();
    //Execute the hint
    const hint_processer = HintProcessor{};

    try hint_processer.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqualSlices(Felt252, &.{}, (try exec_scopes.getValue(std.ArrayList(Felt252), "keys")).items);
    try std.testing.expectEqual(Felt252.fromInt(u256, 3618502761706184546546682988428055018603476541694452277432519575032261771265), try exec_scopes.getValue(Felt252, "key"));

    const access_indices = try exec_scopes.getValue(std.AutoHashMap(Felt252, std.ArrayList(Felt252)), "access_indices");
    try std.testing.expectEqual(1, access_indices.count());
    try std.testing.expectEqualSlices(Felt252, &.{ Felt252.zero(), Felt252.one() }, access_indices.get(Felt252.fromInt(u256, 3618502761706184546546682988428055018603476541694452277432519575032261771265)).?.items);

    //Check ids variables
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 1 }, .{1} },
        .{ .{ 1, 2 }, .{3618502761706184546546682988428055018603476541694452277432519575032261771265} },
    });
}
