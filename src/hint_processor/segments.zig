const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintReference = @import("hint_processor_def.zig").HintReference;
const CairoVM = @import("../vm/core.zig").CairoVM;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const Allocator = std.mem.Allocator;
const hint_codes = @import("builtin_hint_codes.zig");
const hint_utils = @import("hint_utils.zig");
const testing_utils = @import("testing_utils.zig");
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const HintData = @import("hint_processor_def.zig").HintData;

/// This function relocates a segment within the Cairo virtual machine.
///
/// The function takes a pointer to the Cairo virtual machine (`vm`), a hashmap containing variable references (`ids_datas`), and the AP tracking information (`ap_tracking`). It adds a relocation rule using the `addRelocationRule` function of the virtual machine, specifying the source and destination pointers obtained by querying the variable names "src_ptr" and "dest_ptr" using the `getPtrFromVarName` function from the `hint_utils` module.
///
/// This function implements the hint:
/// `%{ memory.add_relocation_rule(src_ptr=ids.src_ptr, dest_ptr=ids.dest_ptr) %}`
///
/// Parameters:
///   - vm: A pointer to the Cairo virtual machine.
///   - ids_datas: A hashmap containing variable references.
///   - ap_tracking: The AP tracking information.
///
/// Returns:
///   - Void if the relocation is successful, or an error if the operation fails.
pub fn relocateSegment(
    vm: *CairoVM,
    ids_datas: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Add a relocation rule to the virtual machine specifying source and destination pointers
    try vm.addRelocationRule(
        // Get the source pointer using the variable name "src_ptr"
        try hint_utils.getPtrFromVarName("src_ptr", vm, ids_datas, ap_tracking),
        // Get the destination pointer using the variable name "dest_ptr"
        try hint_utils.getPtrFromVarName("dest_ptr", vm, ids_datas, ap_tracking),
    );
}

/// This function creates a temporary array within the Cairo virtual machine.
///
/// The function takes an allocator (`allocator`), a pointer to the Cairo virtual machine (`vm`), a hashmap containing variable references (`ids_datas`), and the AP tracking information (`ap_tracking`). It inserts the value representing the temporary array into the virtual machine's memory using the `insertValueFromVarName` function from the `hint_utils` module.
///
/// This function implements the hint:
/// `%{ ids.temporary_array = segments.add_temp_segment() %}`
///
/// Parameters:
///   - allocator: The allocator used for memory operations.
///   - vm: A pointer to the Cairo virtual machine.
///   - ids_datas: A hashmap containing variable references.
///   - ap_tracking: The AP tracking information.
///
/// Returns:
///   - Void if the insertion is successful, or an error if the operation fails.
pub fn temporaryArray(
    allocator: Allocator,
    vm: *CairoVM,
    ids_datas: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Insert the value representing the temporary array into the virtual machine's memory
    try hint_utils.insertValueFromVarName(
        allocator,
        "temporary_array",
        // Convert the relocatable value representing the temporary segment into MaybeRelocatable
        MaybeRelocatable.fromRelocatable(try vm.segments.addTempSegment()),
        vm,
        ids_datas,
        ap_tracking,
    );
}

test "Segments: run relocate segments" {
    // Initializes the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit(); // Ensure cleanup.

    // Sets the frame pointer within the virtual machine to a specific relocatable value.
    vm.run_context.fp.* = 2;

    // Sets up memory segments in the virtual machine with predefined configurations.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{ -2, 0 } },
            .{ .{ 1, 1 }, .{ 3, 0 } },
            .{ .{ 3, 0 }, .{42} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Creates a hashmap containing variable references and insert data.

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "src_ptr", "dest_ptr" });
    defer ids_data.deinit();

    // Executes the hint using the HintProcessor.
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.RELOCATE_SEGMENT, undefined, undefined);

    // Initialize a HintProcessor instance.    // Verifies that the memory relocation operation completes successfully.
    try vm.segments.memory.relocateMemory();
}

test "Segments: run temporary array" {
    // Initializes the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit(); // Ensure cleanup.
    // Ensure cleanup of memory data after execution.
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Sets the frame pointer within the virtual machine to a specific relocatable value.
    vm.run_context.fp.* = 1;

    // Adds memory segments to the virtual machine.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Creates a hashmap containing variable references.
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{"temporary_array"});
    defer ids_data.deinit();

    // Executes the hint using the HintProcessor.
    try testing_utils.runHint(std.testing.allocator, &vm, ids_data, hint_codes.TEMPORARY_ARRAY, undefined, undefined);

    // Verifies that the temporary array was successfully created in the memory segments.
    try expectEqual(
        MaybeRelocatable.fromSegment(-1, 0),
        vm.segments.memory.data.items[1].items[0].?.maybe_relocatable,
    );
}
