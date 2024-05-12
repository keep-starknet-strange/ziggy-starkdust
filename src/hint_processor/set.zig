const std = @import("std");
const Allocator = std.mem.Allocator;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("./hint_processor_def.zig").HintReference;
const hint_utils = @import("./hint_utils.zig");
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const HintData = @import("hint_processor_def.zig").HintData;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const hint_codes = @import("builtin_hint_codes.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;

/// Applies the set addition operation to the provided set.
///
/// This function retrieves pointers and data from the virtual machine and performs set addition operation.
/// It checks if an element is in the set and updates the appropriate variables accordingly.
///
/// # Parameters
/// - `allocator`: Allocator instance for memory allocation.
/// - `vm`: Pointer to the CairoVM instance.
/// - `ids_datas`: StringHashMap containing variable references.
/// - `ap_tracking`: ApTracking instance for AP tracking data.
///
/// # Returns
/// This function returns void if successful. Otherwise, it returns an error indicating the failure reason.
pub fn setAdd(
    allocator: Allocator,
    vm: *CairoVM,
    ids_datas: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Retrieve pointer to the set.
    const set_ptr = try hint_utils.getPtrFromVarName("set_ptr", vm, ids_datas, ap_tracking);

    // Retrieve the size of the element.
    const elm_size: usize = (hint_utils.getIntegerFromVarName("elm_size", vm, ids_datas, ap_tracking) catch
        return MathError.Felt252ToUsizeConversion).toInt(u64) catch
        return MathError.Felt252ToUsizeConversion;

    // Retrieve pointer to the element.
    const elm_ptr = try hint_utils.getPtrFromVarName("elm_ptr", vm, ids_datas, ap_tracking);

    // Retrieve pointer to the end of the set.
    const set_end_ptr = try hint_utils.getPtrFromVarName("set_end_ptr", vm, ids_datas, ap_tracking);

    // Check if the element size is valid.
    if (elm_size == 0) return HintError.AssertionFailed;

    // Check if the set pointer is greater than the end of the set.
    if (set_ptr.gt(set_end_ptr)) return HintError.InvalidSetRange;

    // Calculate the range limit.
    const range_limit = (try set_end_ptr.sub(set_ptr)).offset;

    // Iterate over the set elements.
    for (0..range_limit) |i| {
        // Check if the element is in the set.
        if (try vm.memEq(elm_ptr, try set_ptr.addUint(elm_size * i), elm_size)) {
            // Insert index of the element into the virtual machine.
            try hint_utils.insertValueFromVarName(
                allocator,
                "index",
                MaybeRelocatable.fromInt(u64, i),
                vm,
                ids_datas,
                ap_tracking,
            );

            // Insert indicator that element is in the set into the virtual machine.
            return try hint_utils.insertValueFromVarName(
                allocator,
                "is_elm_in_set",
                MaybeRelocatable.fromFelt(Felt252.one()),
                vm,
                ids_datas,
                ap_tracking,
            );
        }
    }

    // Insert indicator that element is not in the set into the virtual machine.
    return try hint_utils.insertValueFromVarName(
        allocator,
        "is_elm_in_set",
        MaybeRelocatable.fromFelt(Felt252.zero()),
        vm,
        ids_datas,
        ap_tracking,
    );
}

/// Initializes the Cairo virtual machine and creates variable references for hint processing.
///
/// This function initializes the Cairo virtual machine, appends the RangeCheckBuiltinRunner to the list of builtin runners,
/// sets up memory segments based on the provided parameters, and creates a hashmap to store variable references.
///
/// # Parameters
/// - `set_ptr`: A tuple containing the set pointer information. If not provided, default values are used.
/// - `elm_size`: The size of the element. If not provided, a default value is used.
/// - `elm_a`: The value of elm_a. If not provided, a default value is used.
/// - `elm_b`: The value of elm_b. If not provided, a default value is used.
///
/// # Returns
/// A struct containing the initialized Cairo virtual machine and the hashmap of variable references.
/// If initialization is successful, otherwise it returns an error indicating the failure reason.
pub fn initVmIdsData(
    comptime set_ptr: ?std.meta.Tuple(&.{ isize, usize }),
    comptime elm_size: ?i32,
    comptime elm_a: ?isize,
    comptime elm_b: ?usize,
) !struct { vm: CairoVM, ids_data: std.StringHashMap(HintReference) } {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Append the RangeCheckBuiltinRunner to the list of builtin runners.
    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    // Set the fp pointer in run_context.
    vm.run_context.fp = 6;

    // Set default values if not provided.
    const _set_ptr: std.meta.Tuple(&.{ isize, usize }) = set_ptr orelse .{ 2, 0 };
    const _elm_size: i32 = elm_size orelse 2;
    const _elm_a: isize = elm_a orelse 2;
    const _elm_b: usize = elm_b orelse 3;

    // Set up memory segments based on the provided parameters.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 2 }, .{ _set_ptr[0], _set_ptr[1] } },
            .{ .{ 1, 3 }, .{_elm_size} },
            .{ .{ 1, 4 }, .{ 3, 0 } },
            .{ .{ 1, 5 }, .{ 2, 2 } },
            .{ .{ 2, 0 }, .{1} },
            .{ .{ 2, 1 }, .{3} },
            .{ .{ 2, 2 }, .{5} },
            .{ .{ 2, 3 }, .{7} },
            .{ .{ 3, 0 }, .{_elm_a} },
            .{ .{ 3, 1 }, .{_elm_b} },
        },
    );

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);

    // Insert variable references into the hashmap.
    try ids_data.put("is_elm_in_set", HintReference.initSimple(-6));
    try ids_data.put("index", HintReference.initSimple(-5));
    try ids_data.put("set_ptr", HintReference.initSimple(-4));
    try ids_data.put("elm_size", HintReference.initSimple(-3));
    try ids_data.put("elm_ptr", HintReference.initSimple(-2));
    try ids_data.put("set_end_ptr", HintReference.initSimple(-1));

    // Return initialized Cairo virtual machine and hashmap of variable references.
    return .{ .vm = vm, .ids_data = ids_data };
}

test "Set add new element" {
    // Initialize the Cairo virtual machine, set up memory segments, and create variable references.
    var setup = try initVmIdsData(null, null, null, null);
    // Deinitialize the virtual machine, memory segments, and variable references at the end of the test.
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the SET_ADD hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.SET_ADD, setup.ids_data, .{});

    // Execute the hint processor with the provided data.
    try hint_processor.executeHint(std.testing.allocator, &setup.vm, &hint_data, undefined, undefined);

    // Verify that the memory segment at the expected location contains zero.
    try expectEqual(
        MaybeRelocatable.fromFelt(Felt252.zero()),
        setup.vm.segments.memory.get(Relocatable.init(1, 0)),
    );
}

test "Set add already exists" {
    // Initialize the Cairo virtual machine, set up memory segments with specific element pointers,
    // and create variable references.
    var setup = try initVmIdsData(null, null, 1, 3);
    // Deinitialize the virtual machine, memory segments, and variable references at the end of the test.
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the SET_ADD hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.SET_ADD, setup.ids_data, .{});

    // Execute the hint processor with the provided data.
    try hint_processor.executeHint(std.testing.allocator, &setup.vm, &hint_data, undefined, undefined);

    // Verify that the memory segments at the expected locations contain the correct values after the operation.
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 1),
        setup.vm.segments.memory.data.items[1].items[0].?.maybe_relocatable,
    );
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 0),
        setup.vm.segments.memory.data.items[1].items[1].?.maybe_relocatable,
    );
}

test "Set add element size negative" {
    // Initialize the Cairo virtual machine, set up memory segments with a negative element size,
    // and create variable references.
    var setup = try initVmIdsData(null, -2, null, null);
    // Deinitialize the virtual machine, memory segments, and variable references at the end of the test.
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the SET_ADD hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.SET_ADD, setup.ids_data, .{});

    // Verify that the expected error is returned when executing the hint processor.
    try expectError(
        MathError.Felt252ToUsizeConversion,
        hint_processor.executeHint(std.testing.allocator, &setup.vm, &hint_data, undefined, undefined),
    );
}

test "Set add element size is zero" {
    // Initialize the Cairo virtual machine, set up memory segments with an element size of zero,
    // and create variable references.
    var setup = try initVmIdsData(null, 0, null, null);
    // Deinitialize the virtual machine, memory segments, and variable references at the end of the test.
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the SET_ADD hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.SET_ADD, setup.ids_data, .{});

    // Verify that the expected error is returned when executing the hint processor.
    try expectError(
        HintError.AssertionFailed,
        hint_processor.executeHint(std.testing.allocator, &setup.vm, &hint_data, undefined, undefined),
    );
}

test "Set add with set pointer greater than end pointer" {
    // Initialize the Cairo virtual machine, set up memory segments with the provided set pointer and end pointer,
    // and create variable references.
    var setup = try initVmIdsData(.{ 2, 3 }, null, null, null);
    // Deinitialize the virtual machine, memory segments, and variable references at the end of the test.
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the SET_ADD hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.SET_ADD, setup.ids_data, .{});

    // Verify that the expected error is returned when executing the hint processor.
    try expectError(
        HintError.InvalidSetRange,
        hint_processor.executeHint(std.testing.allocator, &setup.vm, &hint_data, undefined, undefined),
    );
}
