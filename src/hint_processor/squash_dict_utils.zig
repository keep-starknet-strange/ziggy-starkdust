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

fn getAccessIndices(
    exec_scopes: *ExecutionScopes,
) !*std.AutoHashMap(Felt252, std.ArrayList(Felt252)) {
    return exec_scopes.getValueRef(std.AutoHashMap(Felt252, std.ArrayList(Felt252)), "access_indices") catch HintError.VariableNotInScopeError;
}

fn cmpByValue(_: void, a: Felt252, b: Felt252) bool {
    return a.lt(b);
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

    std.sort.block(Felt252, current_access_indices.items[0..], {}, cmpByValue);

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
pub fn squashDictInnerLenAssert(exec_scopes: ExecutionScopes) -> Result<(), HintError> {
    //Check that current_access_indices is in scope
    let current_access_indices = exec_scopes.get_list_ref::<Felt252>("current_access_indices")?;
    if !current_access_indices.is_empty() {
        return Err(HintError::CurrentAccessIndicesNotEmpty);
    }
    Ok(())
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
    vm.run_context.fp.* = Relocatable.init(1, 1);
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
    vm.run_context.fp.* = Relocatable.init(1, 1);
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
    vm.run_context.fp.* = Relocatable.init(1, 1);
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
    vm.run_context.fp.* = Relocatable.init(1, 1);

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
    vm.run_context.fp.* = Relocatable.init(1, 1);

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
    vm.run_context.fp.* = Relocatable.init(1, 1);
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
    vm.run_context.fp.* = Relocatable.init(1, 1);
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
    vm.run_context.fp.* = Relocatable.init(1, 1);
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
    vm.run_context.fp.* = Relocatable.init(1, 1);
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
