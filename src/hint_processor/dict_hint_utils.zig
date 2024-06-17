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

//DictAccess struct has three memebers, so the size of DictAccess* is 3
pub const DICT_ACCESS_SIZE = 3;

pub fn copyInitialDict(exec_scopes: *ExecutionScopes) !?std.AutoHashMap(MaybeRelocatable, MaybeRelocatable) {
    const dict = exec_scopes.getValue(std.AutoHashMap(MaybeRelocatable, MaybeRelocatable), "initial_dict") catch return null;

    return try dict.clone();
}

// Implements hint:
//    if '__dict_manager' not in globals():
//            from starkware.cairo.common.dict import DictManager
//            __dict_manager = DictManager()

//        memory[ap] = __dict_manager.new_dict(segments, initial_dict)
//        del initial_dict

// For now, the functionality to create a dictionary from a previously defined initial_dict (using a hint)
// is not available
pub fn dictInit(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
) !void {
    //Get initial dictionary from scope (defined by an earlier hint)
    const initial_dict = (copyInitialDict(exec_scopes) catch null) orelse return HintError.NoInitialDict;
    //Check if there is a dict manager in scope, create it if there isnt one
    var base: MaybeRelocatable = undefined;

    if (exec_scopes.getDictManager()) |dict_manager_rc| {
        defer dict_manager_rc.releaseWithFn(DictManager.deinit);
        base = try dict_manager_rc.value.initDict(vm, initial_dict);
    } else |_| {
        var dict_manager = try DictManager.init(allocator);
        errdefer dict_manager.deinit();

        base = try dict_manager.initDict(vm, initial_dict);
        try exec_scopes.assignOrUpdateVariable("dict_manager", .{ .dict_manager = try Rc(DictManager).init(allocator, dict_manager) });
    }

    try hint_utils.insertValueIntoAp(allocator, vm, base);
}

//    if '__dict_manager' not in globals():
//             from starkware.cairo.common.dict import DictManager
//             __dict_manager = DictManager()

//         memory[ap] = __dict_manager.new_default_dict(segments, ids.default_value)

// For now, the functionality to create a dictionary from a previously defined initial_dict (using a hint)
// is not available, an empty dict is created always
pub fn defaultDictNew(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //Check that ids contains the reference id for each variable used by the hint
    const default_value =
        try hint_utils.getMaybeRelocatableFromVarName("default_value", vm, ids_data, ap_tracking);
    //Get initial dictionary from scope (defined by an earlier hint) if available
    const initial_dict = try copyInitialDict(exec_scopes);
    //Check if there is a dict manager in scope, create it if there isnt one
    var base: MaybeRelocatable = undefined;
    if (exec_scopes.getDictManager()) |dict_manager_rc| {
        defer dict_manager_rc.releaseWithFn(DictManager.deinit);
        base = try dict_manager_rc.value
            .initDefaultDict(allocator, vm, default_value, initial_dict);
    } else |_| {
        var dict_manager = try DictManager.init(allocator);
        errdefer dict_manager.deinit();
        base = try dict_manager.initDefaultDict(allocator, vm, default_value, initial_dict);
        try exec_scopes.assignOrUpdateVariable("dict_manager", .{ .dict_manager = try Rc(DictManager).init(allocator, dict_manager) });
    }

    try hint_utils.insertValueIntoAp(allocator, vm, base);
}

// Implements hint:
//   dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
//   dict_tracker.current_ptr += ids.DictAccess.SIZE
//   ids.value = dict_tracker.data[ids.key]
pub fn dictRead(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const key = try hint_utils.getMaybeRelocatableFromVarName("key", vm, ids_data, ap_tracking);
    const dict_ptr = try hint_utils.getPtrFromVarName("dict_ptr", vm, ids_data, ap_tracking);
    var dict_rc = try exec_scopes.getDictManager();
    defer dict_rc.releaseWithFn(DictManager.deinit);

    var tracker = try dict_rc.value.getTrackerRef(dict_ptr);
    tracker.current_ptr.offset = tracker.current_ptr.offset + DICT_ACCESS_SIZE;

    try hint_utils.insertValueFromVarName(allocator, "value", try tracker.getValue(key), vm, ids_data, ap_tracking);
}

// Implements hint:
//     dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
//     dict_tracker.current_ptr += ids.DictAccess.SIZE
//     ids.dict_ptr.prev_value = dict_tracker.data[ids.key]
//     dict_tracker.data[ids.key] = ids.new_value
pub fn dictWrite(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const key = try hint_utils.getMaybeRelocatableFromVarName("key", vm, ids_data, ap_tracking);
    const new_value = try hint_utils.getMaybeRelocatableFromVarName("new_value", vm, ids_data, ap_tracking);
    const dict_ptr = try hint_utils.getPtrFromVarName("dict_ptr", vm, ids_data, ap_tracking);
    //Get tracker for dictionary
    var dict_rc = try exec_scopes.getDictManager();
    defer dict_rc.releaseWithFn(DictManager.deinit);
    var tracker = try dict_rc.value.getTrackerRef(dict_ptr);
    //dict_ptr is a pointer to a struct, with the ordered fields (key, prev_value, new_value),
    //dict_ptr.prev_value will be equal to dict_ptr + 1
    const dict_ptr_prev_value = try dict_ptr.addUint(1);
    //Tracker set to track next dictionary entry
    tracker.current_ptr.offset = tracker.current_ptr.offset + DICT_ACCESS_SIZE;
    //Get previous value
    const prev_value = try tracker.getValue(key);
    //Insert new value into tracker
    try tracker.insertValue(key, new_value);
    //Insert previous value into dict_ptr.prev_value
    //Addres for dict_ptr.prev_value should be dict_ptr* + 1 (defined above)
    try vm.insertInMemory(allocator, dict_ptr_prev_value, prev_value);
}

// Implements hint:
//    # Verify dict pointer and prev value.
//        dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
//        current_value = dict_tracker.data[ids.key]
//        assert current_value == ids.prev_value, \
//            f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'

//        # Update value.
//        dict_tracker.data[ids.key] = ids.new_value
//        dict_tracker.current_ptr += ids.DictAccess.SIZE
pub fn dictUpdate(
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const key = try hint_utils.getMaybeRelocatableFromVarName("key", vm, ids_data, ap_tracking);
    const prev_value = try hint_utils.getMaybeRelocatableFromVarName("prev_value", vm, ids_data, ap_tracking);
    const new_value = try hint_utils.getMaybeRelocatableFromVarName("new_value", vm, ids_data, ap_tracking);
    const dict_ptr = try hint_utils.getPtrFromVarName("dict_ptr", vm, ids_data, ap_tracking);

    //Get tracker for dictionary
    var dict_rc = try exec_scopes.getDictManager();
    defer dict_rc.releaseWithFn(DictManager.deinit);

    var tracker = try dict_rc.value.getTrackerRef(dict_ptr);
    //Check that prev_value is equal to the current value at the given key
    const current_value = try tracker.getValue(key);
    if (!current_value.eq(prev_value)) {
        return HintError.WrongPrevValue;
    }
    //Update Value
    try tracker.insertValue(key, new_value);
    tracker.current_ptr.offset = tracker.current_ptr.offset + DICT_ACCESS_SIZE;
}

// Implements hint:
//    # Prepare arguments for dict_new. In particular, the same dictionary values should be copied
//    # to the new (squashed) dictionary.
//    vm_enter_scope({
//        # Make __dict_manager accessible.
//        '__dict_manager': __dict_manager,
//        # Create a copy of the dict, in case it changes in the future.
//        'initial_dict': dict(__dict_manager.get_dict(ids.dict_accesses_end)),
//    })
pub fn dictSquashCopyDict(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const dict_accesses_end = try hint_utils.getPtrFromVarName("dict_accesses_end", vm, ids_data, ap_tracking);
    // dont release because we put in scope.put dict_manager
    const dict_manager_rc = try exec_scopes.getDictManager();
    const dict_copy = try (try dict_manager_rc.value
        .getTracker(dict_accesses_end))
        .getDictionaryCopy();

    var scope = std.StringHashMap(HintType).init(allocator);
    errdefer scope.deinit();

    try scope.put("dict_manager", .{ .dict_manager = dict_manager_rc });
    try scope.put("initial_dict", .{ .maybe_relocatable_map = dict_copy });

    try exec_scopes.enterScope(scope);
}

// Implements Hint:
//    # Update the DictTracker's current_ptr to point to the end of the squashed dict.
//    __dict_manager.get_tracker(ids.squashed_dict_start).current_ptr = \
//    ids.squashed_dict_end.address_
pub fn dictSquashUpdatePtr(
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const squashed_dict_start =
        try hint_utils.getPtrFromVarName("squashed_dict_start", vm, ids_data, ap_tracking);
    const squashed_dict_end = try hint_utils.getPtrFromVarName("squashed_dict_end", vm, ids_data, ap_tracking);

    var dict_manager_rc = try exec_scopes
        .getDictManager();
    defer dict_manager_rc.releaseWithFn(DictManager.deinit);

    var tracker = try (dict_manager_rc.value.getTrackerRef(squashed_dict_start));

    tracker.current_ptr = squashed_dict_end;
}

test "DictHintUtils: dictInit with no initial dict" {
    const hint_code = "if '__dict_manager' not in globals():\n    from starkware.cairo.common.dict import DictManager\n    __dict_manager = DictManager()\n\nmemory[ap] = __dict_manager.new_dict(segments, initial_dict)\ndel initial_dict";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.addMemorySegment();

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = std.StringHashMap(HintReference).init(std.testing.allocator),
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try std.testing.expectError(HintError.NoInitialDict, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "DictHintUtils: dictInit with initial_dict" {
    const hint_code = "if '__dict_manager' not in globals():\n    from starkware.cairo.common.dict import DictManager\n    __dict_manager = DictManager()\n\nmemory[ap] = __dict_manager.new_dict(segments, initial_dict)\ndel initial_dict";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.addMemorySegment();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("initial_dict", .{
        .maybe_relocatable_map = std.AutoHashMap(MaybeRelocatable, MaybeRelocatable).init(std.testing.allocator),
    });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = std.StringHashMap(HintReference).init(std.testing.allocator),
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqual(2, vm.segments.numSegments());
    try std.testing.expectEqual(Relocatable.init(1, 0), try vm.getRelocatable(Relocatable.init(1, 0)));

    const dict_manager_rc = try exec_scopes.getDictManager();
    defer dict_manager_rc.releaseWithFn(DictManager.deinit);

    try std.testing.expectEqual(Relocatable.init(1, 0), dict_manager_rc.value.trackers.get(1).?.current_ptr);
    try std.testing.expectEqual(0, dict_manager_rc.value.trackers.get(1).?.data.SimpleDictionary.count());
}

test "DictHintUtils: dictRead valid" {
    const hint_code = "dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ndict_tracker.current_ptr += ids.DictAccess.SIZE\nids.value = dict_tracker.data[ids.key]";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.addMemorySegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 2 }, .{ 2, 0 } },
    });
    vm.run_context.fp = 3;

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{
        .{ 5, 12 },
    });

    const hint_processor = HintProcessor{};
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "key", "value", "dict_ptr",
    });

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    //Check that value variable (at address (1,1)) contains the proper value
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 12), vm.segments.memory.get(Relocatable.init(1, 1)));
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
}

test "DictHintUtils: dictRead invalid key" {
    const hint_code = "dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ndict_tracker.current_ptr += ids.DictAccess.SIZE\nids.value = dict_tracker.data[ids.key]";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.addMemorySegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{6} },
        .{ .{ 1, 2 }, .{ 2, 0 } },
    });
    vm.run_context.fp = 3;

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{
        .{ 5, 12 },
    });

    const hint_processor = HintProcessor{};
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "key", "value", "dict_ptr",
    });

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try std.testing.expectError(
        HintError.NoValueForKey,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes),
    );
}

test "DictHintUtils: dictRead no tracker" {
    const hint_code = "dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ndict_tracker.current_ptr += ids.DictAccess.SIZE\nids.value = dict_tracker.data[ids.key]";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    _ = try vm.addMemorySegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{6} },
        .{ .{ 1, 2 }, .{ 2, 0 } },
    });
    vm.run_context.fp = 3;

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("dict_manager", .{ .dict_manager = try Rc(DictManager).init(std.testing.allocator, try DictManager.init(std.testing.allocator)) });

    const hint_processor = HintProcessor{};
    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "key", "value", "dict_ptr",
    });

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try std.testing.expectError(
        HintError.NoDictTracker,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes),
    );
}

test "DictHintUtils: defaultDictInit valid" {
    const hint_code = "if '__dict_manager' not in globals():\n    from starkware.cairo.common.dict import DictManager\n    __dict_manager = DictManager()\n\nmemory[ap] = __dict_manager.new_default_dict(segments, ids.default_value)";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 1;
    vm.run_context.fp = 1;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{17} },
    });

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"default_value"});

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqual(3, vm.segments.memory.data.items.len);
    try std.testing.expectEqual(Relocatable.init(2, 0), try vm.getRelocatable(Relocatable.init(1, 1)));

    const dict_manager_rc = try exec_scopes.getDictManager();
    defer dict_manager_rc.releaseWithFn(DictManager.deinit);

    try std.testing.expectEqual(Relocatable.init(2, 0), dict_manager_rc.value.trackers.get(2).?.current_ptr);
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 17), dict_manager_rc.value.trackers.get(2).?.data.DefaultDictionary.default_value);
    try std.testing.expectEqual(0, dict_manager_rc.value.trackers.get(2).?.data.DefaultDictionary.dict.count());
}

test "DictHintUtils: dictWrite valid empty dict" {
    const hint_code = "dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ndict_tracker.current_ptr += ids.DictAccess.SIZE\nids.dict_ptr.prev_value = dict_tracker.data[ids.key]\ndict_tracker.data[ids.key] = ids.new_value";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManagerDefault(std.testing.allocator, &exec_scopes, 2, 2, &.{});

    vm.run_context.fp = 3;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{17} },
        .{ .{ 1, 2 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictionary(&exec_scopes, 2, &.{.{ 5, 17 }});
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
    try std.testing.expectEqual(Felt252.fromInt(u8, 2), try vm.getFelt(Relocatable.init(2, 1)));
}

test "DictHintUtils: dictWriteSimple valid overwrite value" {
    const hint_code = "dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ndict_tracker.current_ptr += ids.DictAccess.SIZE\nids.dict_ptr.prev_value = dict_tracker.data[ids.key]\ndict_tracker.data[ids.key] = ids.new_value";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{.{ 5, 10 }});

    vm.run_context.fp = 3;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{17} },
        .{ .{ 1, 2 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictionary(&exec_scopes, 2, &.{.{ 5, 17 }});
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
    try std.testing.expectEqual(Felt252.fromInt(u8, 10), try vm.getFelt(Relocatable.init(2, 1)));
}

test "DictHintUtils: dictUpdate simple valid" {
    const hint_code = "# Verify dict pointer and prev value.\ndict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ncurrent_value = dict_tracker.data[ids.key]\nassert current_value == ids.prev_value, \\\n    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'\n\n# Update value.\ndict_tracker.data[ids.key] = ids.new_value\ndict_tracker.current_ptr += ids.DictAccess.SIZE";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{.{ 5, 10 }});

    vm.run_context.fp = 4;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{10} },
        .{ .{ 1, 2 }, .{20} },
        .{ .{ 1, 3 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "prev_value", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictionary(&exec_scopes, 2, &.{.{ 5, 20 }});
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
}

test "DictHintUtils: dictUpdate simple valid no change" {
    const hint_code = "# Verify dict pointer and prev value.\ndict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ncurrent_value = dict_tracker.data[ids.key]\nassert current_value == ids.prev_value, \\\n    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'\n\n# Update value.\ndict_tracker.data[ids.key] = ids.new_value\ndict_tracker.current_ptr += ids.DictAccess.SIZE";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{.{ 5, 10 }});

    vm.run_context.fp = 4;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{10} },
        .{ .{ 1, 2 }, .{10} },
        .{ .{ 1, 3 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "prev_value", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictionary(&exec_scopes, 2, &.{.{ 5, 10 }});
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
}

test "DictHintUtils: dictUpdate simple invalid wrong prev key" {
    const hint_code = "# Verify dict pointer and prev value.\ndict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ncurrent_value = dict_tracker.data[ids.key]\nassert current_value == ids.prev_value, \\\n    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'\n\n# Update value.\ndict_tracker.data[ids.key] = ids.new_value\ndict_tracker.current_ptr += ids.DictAccess.SIZE";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{.{ 5, 10 }});

    vm.run_context.fp = 4;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{11} },
        .{ .{ 1, 2 }, .{20} },
        .{ .{ 1, 3 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "prev_value", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try std.testing.expectError(HintError.WrongPrevValue, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "DictHintUtils: dictUpdate default valid no change" {
    const hint_code = "# Verify dict pointer and prev value.\ndict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ncurrent_value = dict_tracker.data[ids.key]\nassert current_value == ids.prev_value, \\\n    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'\n\n# Update value.\ndict_tracker.data[ids.key] = ids.new_value\ndict_tracker.current_ptr += ids.DictAccess.SIZE";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManagerDefault(std.testing.allocator, &exec_scopes, 2, 2, &.{.{ 5, 10 }});

    vm.run_context.fp = 4;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{10} },
        .{ .{ 1, 2 }, .{10} },
        .{ .{ 1, 3 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "prev_value", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictionary(&exec_scopes, 2, &.{.{ 5, 10 }});
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
}

test "DictHintUtils: dictUpdate default valid" {
    const hint_code = "# Verify dict pointer and prev value.\ndict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ncurrent_value = dict_tracker.data[ids.key]\nassert current_value == ids.prev_value, \\\n    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'\n\n# Update value.\ndict_tracker.data[ids.key] = ids.new_value\ndict_tracker.current_ptr += ids.DictAccess.SIZE";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManagerDefault(std.testing.allocator, &exec_scopes, 2, 2, &.{.{ 5, 10 }});

    vm.run_context.fp = 4;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{10} },
        .{ .{ 1, 2 }, .{20} },
        .{ .{ 1, 3 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "prev_value", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictionary(&exec_scopes, 2, &.{.{ 5, 20 }});
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
}

test "DictHintUtils: dictUpdate default invalid wrong prev key" {
    const hint_code = "# Verify dict pointer and prev value.\ndict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ncurrent_value = dict_tracker.data[ids.key]\nassert current_value == ids.prev_value, \\\n    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'\n\n# Update value.\ndict_tracker.data[ids.key] = ids.new_value\ndict_tracker.current_ptr += ids.DictAccess.SIZE";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManagerDefault(std.testing.allocator, &exec_scopes, 2, 2, &.{.{ 5, 10 }});

    vm.run_context.fp = 4;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{11} },
        .{ .{ 1, 2 }, .{10} },
        .{ .{ 1, 3 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "prev_value", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try std.testing.expectError(HintError.WrongPrevValue, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "DictHintUtils: dictUpdate default valid no key prev value equals default" {
    const hint_code = "# Verify dict pointer and prev value.\ndict_tracker = __dict_manager.get_tracker(ids.dict_ptr)\ncurrent_value = dict_tracker.data[ids.key]\nassert current_value == ids.prev_value, \\\n    f'Wrong previous value in dict. Got {ids.prev_value}, expected {current_value}.'\n\n# Update value.\ndict_tracker.data[ids.key] = ids.new_value\ndict_tracker.current_ptr += ids.DictAccess.SIZE";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManagerDefault(std.testing.allocator, &exec_scopes, 2, 17, &.{});

    vm.run_context.fp = 4;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{17} },
        .{ .{ 1, 2 }, .{20} },
        .{ .{ 1, 3 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "prev_value", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictionary(&exec_scopes, 2, &.{.{ 5, 20 }});
    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
}

test "DictHintUtils: dictSquashCopyDict valid empty dict" {
    const hint_code = "# Prepare arguments for dict_new. In particular, the same dictionary values should be copied\n# to the new (squashed) dictionary.\nvm_enter_scope({\n    # Make __dict_manager accessible.\n    '__dict_manager': __dict_manager,\n    # Create a copy of the dict, in case it changes in the future.\n    'initial_dict': dict(__dict_manager.get_dict(ids.dict_accesses_end)),\n})";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{});

    vm.run_context.fp = 1;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses_end",
    });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqual(2, exec_scopes.data.items.len);

    //Check that this scope contains the expected initial-dict
    const variables = exec_scopes.getLocalVariable().?;
    try std.testing.expectEqual(2, variables.count()); //Two of them, as DictManager is also there
    try std.testing.expectEqual(
        0,
        variables.get("initial_dict").?.maybe_relocatable_map.count(),
    );
}

test "DictHintUtils: dictSquashCopyDict valid non-empty dict" {
    const hint_code = "# Prepare arguments for dict_new. In particular, the same dictionary values should be copied\n# to the new (squashed) dictionary.\nvm_enter_scope({\n    # Make __dict_manager accessible.\n    '__dict_manager': __dict_manager,\n    # Create a copy of the dict, in case it changes in the future.\n    'initial_dict': dict(__dict_manager.get_dict(ids.dict_accesses_end)),\n})";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{ .{ 1, 2 }, .{ 3, 4 }, .{ 5, 6 } });

    vm.run_context.fp = 1;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "dict_accesses_end",
    });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try std.testing.expectEqual(2, exec_scopes.data.items.len);

    //Check that this scope contains the expected initial-dict
    const variables = exec_scopes.getLocalVariable().?;
    try std.testing.expectEqual(2, variables.count()); //Two of them, as DictManager is also there
    try std.testing.expectEqual(
        3,
        variables.get("initial_dict").?.maybe_relocatable_map.count(),
    );

    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 2), variables.get("initial_dict").?.maybe_relocatable_map.get(MaybeRelocatable.fromInt(u8, 1)).?);
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 4), variables.get("initial_dict").?.maybe_relocatable_map.get(MaybeRelocatable.fromInt(u8, 3)).?);
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 6), variables.get("initial_dict").?.maybe_relocatable_map.get(MaybeRelocatable.fromInt(u8, 5)).?);
}

test "DictHintUtils: dictSquashUpdate ptr no tracker" {
    const hint_code = "# Update the DictTracker's current_ptr to point to the end of the squashed dict.\n__dict_manager.get_tracker(ids.squashed_dict_start).current_ptr = \\\n    ids.squashed_dict_end.address_";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("dict_manager", .{
        .dict_manager = try Rc(DictManager).init(std.testing.allocator, try DictManager.init(std.testing.allocator)),
    });

    vm.run_context.fp = 2;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{ 2, 3 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "squashed_dict_start", "squashed_dict_end",
    });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try std.testing.expectError(HintError.NoDictTracker, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "DictHintUtils: dictSquashUpdate ptr valid" {
    const hint_code = "# Update the DictTracker's current_ptr to point to the end of the squashed dict.\n__dict_manager.get_tracker(ids.squashed_dict_start).current_ptr = \\\n    ids.squashed_dict_end.address_";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{.{ 1, 2 }});

    vm.run_context.fp = 2;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 1, 1 }, .{ 2, 3 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "squashed_dict_start", "squashed_dict_end",
    });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    try testing_utils.checkDictPtr(&exec_scopes, 2, Relocatable.init(2, 3));
}

test "DictHintUtils: dictSquashUpdate ptr mismatched dict ptr" {
    const hint_code = "# Update the DictTracker's current_ptr to point to the end of the squashed dict.\n__dict_manager.get_tracker(ids.squashed_dict_start).current_ptr = \\\n    ids.squashed_dict_end.address_";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManager(std.testing.allocator, &exec_scopes, 2, &.{.{ 1, 2 }});

    vm.run_context.fp = 2;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{ 2, 3 } },
        .{ .{ 1, 1 }, .{ 2, 6 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "squashed_dict_start", "squashed_dict_end",
    });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_code,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try std.testing.expectError(HintError.MismatchedDictPtr, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "DictHintUtils: dictWrite valid relocatable new value" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try testing_utils.initDictManagerDefault(std.testing.allocator, &exec_scopes, 2, 2, &.{});

    vm.run_context.fp = 3;

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{5} },
        .{ .{ 1, 1 }, .{ 1, 7 } },
        .{ .{ 1, 2 }, .{ 2, 0 } },
    });
    _ = try vm.addMemorySegment();

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "key", "new_value", "dict_ptr" });

    const hint_processor = HintProcessor{};

    var hint_data =
        HintData{
        .code = hint_codes.DICT_WRITE,
        .ids_data = ids_data,
        .ap_tracking = undefined,
    };
    defer hint_data.deinit();

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    var dict_manager_rc = try exec_scopes.getDictManager();
    defer dict_manager_rc.releaseWithFn(DictManager.deinit);

    var tracker = dict_manager_rc.value.trackers.get(2).?;
    try std.testing.expectEqual(MaybeRelocatable.fromInt(u8, 2), tracker.data.DefaultDictionary.default_value);
    try std.testing.expectEqual(1, tracker.data.DefaultDictionary.dict.count());
    try std.testing.expectEqual(MaybeRelocatable.fromRelocatable(Relocatable.init(1, 7)), tracker.data.DefaultDictionary.dict.get(MaybeRelocatable.fromInt(u8, 5)).?);
    try std.testing.expectEqual(Relocatable.init(2, 3), tracker.current_ptr);
}
