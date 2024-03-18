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
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const HintError = @import("../vm/error.zig").HintError;
const MathError = @import("../vm/error.zig").MathError;

/// Find Element
///
/// Searches for an element in an array based on the provided key.
/// Updates the index variable if the element is found.
///
/// Parameters:
/// - `allocator`: The memory allocator.
/// - `vm`: The Cairo virtual machine.
/// - `exec_scopes`: Execution scopes containing stored variables.
/// - `ids_datas`: Variable references hashmap.
/// - `ap_tracking`: Tracking information for the allocation points.
///
/// Returns:
/// - `void`: Returns nothing if successful.
///
/// Errors:
/// - `HintError.ValueOutsideValidRange`: When the provided element size is outside the valid range.
/// - `MathError.Felt252ToUsizeConversion`: When there is an error converting a Felt252 value to usize.
/// - `HintError.KeyNotFound`: When the provided key is not found in the array.
/// - `HintError.InvalidIndex`: When the stored index does not match the provided key.
/// - `HintError.FindElemMaxSize`: When the maximum size of elements to search is exceeded.
/// - `HintError.NoValueForKeyFindElement`: When the provided key is not found in the array.
pub fn findElement(
    allocator: Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_datas: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Retrieve key, element size, number of elements, and array start pointer.
    const key = try hint_utils.getIntegerFromVarName("key", vm, ids_datas, ap_tracking);
    const elm_size_bigint = (try hint_utils.getIntegerFromVarName("elm_size", vm, ids_datas, ap_tracking)).toInteger();
    const n_elms = try hint_utils.getIntegerFromVarName("n_elms", vm, ids_datas, ap_tracking);
    const array_start = try hint_utils.getPtrFromVarName("array_ptr", vm, ids_datas, ap_tracking);

    // Retrieve find element index from execution scopes if available.
    const find_element_index = exec_scopes.getFelt("find_element_index") catch null;

    // Convert element size to usize if within valid range.
    const elm_size = if (elm_size_bigint <= std.math.maxInt(usize) and elm_size_bigint > 0)
        @as(usize, @intCast(elm_size_bigint))
    else
        return HintError.ValueOutsideValidRange;

    if (find_element_index) |find_element_index_value| {
        // Retrieve the key at the calculated index.
        const find_element_index_usize: usize = find_element_index_value.intoU64() catch
            return MathError.Felt252ToUsizeConversion;
        const found_key = vm.getFelt(array_start.addUint(elm_size * find_element_index_usize) catch
            return HintError.KeyNotFound) catch
            return HintError.KeyNotFound;

        // Compare the retrieved key with the provided key.
        if (!found_key.equal(key)) return HintError.InvalidIndex;

        // Update the index variable and delete the stored index.
        try hint_utils.insertValueFromVarName(
            allocator,
            "index",
            MaybeRelocatable.fromFelt(find_element_index_value),
            vm,
            ids_datas,
            ap_tracking,
        );
        exec_scopes.deleteVariable("find_element_index");
    } else {
        // Check if the maximum size of elements to search is defined and exceeded.
        if (exec_scopes.getFelt("find_element_max_size") catch null) |find_element_max_size| {
            if (n_elms.gt(find_element_max_size)) return HintError.FindElemMaxSize;
        }

        // Convert the number of elements to search to u32.
        const n_elms_int = n_elms.toInteger();
        const n_elms_iter: u32 = if (n_elms_int <= std.math.maxInt(u32))
            @intCast(n_elms_int)
        else
            return MathError.Felt252ToUsizeConversion;

        // Iterate through the array to find the key.
        for (0..n_elms_iter) |i| {
            const iter_key = vm.getFelt(array_start.addUint(elm_size * i) catch
                return HintError.KeyNotFound) catch
                return HintError.KeyNotFound;
            if (iter_key.equal(key)) {
                // Update the index variable if the key is found.
                return try hint_utils.insertValueFromVarName(
                    allocator,
                    "index",
                    MaybeRelocatable.fromFelt(Felt252.fromInt(u256, i)),
                    vm,
                    ids_datas,
                    ap_tracking,
                );
            }
        }

        // Return an error if the key is not found.
        return HintError.NoValueForKeyFindElement;
    }
}

/// Search Sorted Lower
///
/// Searches for the lower bound in a sorted array for the provided key.
/// Updates the index variable with the lower bound.
///
/// Parameters:
/// - `allocator`: The memory allocator.
/// - `vm`: The Cairo virtual machine.
/// - `exec_scopes`: Execution scopes containing stored variables.
/// - `ids_datas`: Variable references hashmap.
/// - `ap_tracking`: Tracking information for the allocation points.
///
/// Returns:
/// - `void`: Returns nothing if successful.
///
/// Errors:
/// - `HintError.ValueOutsideValidRange`: When the provided element size is outside the valid range.
/// - `HintError.FindElemMaxSize`: When the maximum size of elements to search is exceeded.
/// - `HintError.KeyNotFound`: When the provided key is not found in the array.
pub fn searchSortedLower(
    allocator: Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_datas: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Retrieve maximum element size, number of elements, array pointer, element size, and key.
    const find_element_max_size = exec_scopes.getFelt("find_element_max_size") catch null;
    const n_elms = (try hint_utils.getIntegerFromVarName("n_elms", vm, ids_datas, ap_tracking)).toInteger();
    const rel_array_ptr = try hint_utils.getRelocatableFromVarName("array_ptr", vm, ids_datas, ap_tracking);
    const elm_size = (try hint_utils.getIntegerFromVarName("elm_size", vm, ids_datas, ap_tracking)).toInteger();
    const key = try hint_utils.getIntegerFromVarName("key", vm, ids_datas, ap_tracking);

    // Check if the element size is valid.
    if (elm_size == 0) return HintError.ValueOutsideValidRange;

    // Check if the maximum size of elements to search is defined and exceeded.
    if (find_element_max_size) |max_size| {
        if (n_elms > max_size.toInteger()) return HintError.FindElemMaxSize;
    }

    // Retrieve the array iterator and convert number of elements and element size to usize.
    var array_iter = try vm.getRelocatable(rel_array_ptr);
    const n_elms_usize: usize = if (n_elms <= std.math.maxInt(usize))
        @intCast(n_elms)
    else
        return HintError.KeyNotFound;
    const elm_size_usize: usize = if (elm_size <= std.math.maxInt(usize))
        @intCast(elm_size)
    else
        return HintError.KeyNotFound;

    // Iterate through the array to find the lower bound for the key.
    for (0..n_elms_usize) |i| {
        const value = try vm.getFelt(array_iter);
        if (value.ge(key)) {
            // Update the index variable if the lower bound is found.
            return try hint_utils.insertValueFromVarName(
                allocator,
                "index",
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, i)),
                vm,
                ids_datas,
                ap_tracking,
            );
        }
        array_iter.offset += elm_size_usize;
    }

    // Update the index variable with the number of elements if the lower bound is not found.
    try hint_utils.insertValueFromVarName(
        allocator,
        "index",
        MaybeRelocatable.fromFelt(Felt252.fromInt(u256, n_elms)),
        vm,
        ids_datas,
        ap_tracking,
    );
}

/// Initialize VM IDs Data
///
/// Initializes Cairo virtual machine and variable references hashmap.
/// Allocates memory space and sets default values if provided.
///
/// Parameters:
/// - `values_to_override`: Optional hashmap containing values to override the default ones.
///
/// Returns:
/// - `struct { vm: CairoVM, ids_data: std.StringHashMap(HintReference) }`: Initialized VM and IDs data.
pub fn initVmIdsData(
    values_to_override: *std.StringHashMap(MaybeRelocatable),
) !struct { vm: CairoVM, ids_data: std.StringHashMap(HintReference) } {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});

    // Set the starting offset for the frame pointer.
    const fp_offset_start: usize = 4;
    vm.run_context.fp.* = fp_offset_start;

    // Allocate memory space.
    inline for (0..3) |_| _ = try vm.addMemorySegment();

    // Define memory cell addresses and default values.
    const addresses = [_]Relocatable{
        Relocatable.init(1, 0),
        Relocatable.init(1, 1),
        Relocatable.init(1, 2),
        Relocatable.init(1, 4),
        Relocatable.init(2, 0),
        Relocatable.init(2, 1),
        Relocatable.init(2, 2),
        Relocatable.init(2, 3),
    };
    const default_values = [_]std.meta.Tuple(&.{ []const u8, MaybeRelocatable }){
        .{ "array_ptr", MaybeRelocatable.fromSegment(2, 0) },
        .{ "elm_size", MaybeRelocatable.fromInt(u32, 2) },
        .{ "n_elms", MaybeRelocatable.fromInt(u32, 2) },
        .{ "key", MaybeRelocatable.fromInt(u32, 3) },
        .{ "arr[0].a", MaybeRelocatable.fromFelt(Felt252.one()) },
        .{ "arr[0].b", MaybeRelocatable.fromInt(u32, 2) },
        .{ "arr[1].a", MaybeRelocatable.fromInt(u32, 3) },
        .{ "arr[1].b", MaybeRelocatable.fromInt(u32, 4) },
    };

    // Set default values for memory cells, overriding if provided.
    for (addresses, 0..) |memory_cell, i| {
        try vm.segments.memory.set(
            std.testing.allocator,
            memory_cell,
            values_to_override.get(default_values[i][0]) orelse default_values[i][1],
        );
    }

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);

    // Set variable references for predefined names.
    for ([_][]const u8{ "array_ptr", "elm_size", "n_elms", "index", "key" }, 0..) |name, i| {
        try ids_data.put(
            name,
            HintReference.initSimple(@as(i32, @intCast(i)) - @as(i32, @intCast(fp_offset_start))),
        );
    }

    return .{ .vm = vm, .ids_data = ids_data };
}

test "Element found by search" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    // Execute the hint processor with the provided data.
    try hint_processor.executeHint(
        std.testing.allocator,
        &setup.vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 1),
        setup.vm.segments.memory.data.items[1].items[3].?.maybe_relocatable,
    );
}

test "Element found by oracle" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    try exec_scopes.assignOrUpdateVariable("find_element_index", .{ .felt = Felt252.one() });

    // Execute the hint processor with the provided data.
    try hint_processor.executeHint(
        std.testing.allocator,
        &setup.vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 1),
        setup.vm.segments.memory.data.items[1].items[3].?.maybe_relocatable,
    );
}

test "Element not found search" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("key", MaybeRelocatable.fromInt(u8, 7));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.NoValueForKeyFindElement,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Element not found oracle" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    try exec_scopes.assignOrUpdateVariable("find_element_index", .{ .felt = Felt252.fromInt(u8, 2) });

    try expectError(
        HintError.KeyNotFound,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element failed ids get from memory" {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    vm.run_context.fp.* = 5;

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Insert variable references into the hashmap.
    try ids_data.put("array_ptr", HintReference.initSimple(-5));
    try ids_data.put("elm_size", HintReference.initSimple(-4));
    try ids_data.put("n_elms", HintReference.initSimple(-3));
    try ids_data.put("index", HintReference.initSimple(-2));
    try ids_data.put("key", HintReference.initSimple(-1));

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(
            std.testing.allocator,
            &vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element with non integer element size" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("elm_size", MaybeRelocatable.fromSegment(7, 8));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element with 0 element size" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("elm_size", MaybeRelocatable.fromFelt(Felt252.zero()));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.ValueOutsideValidRange,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element with negative element size" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("elm_size", MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 2).neg()));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.ValueOutsideValidRange,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element not in number of elements" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("n_elms", MaybeRelocatable.fromSegment(1, 2));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element with negative number of elements" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("n_elms", MaybeRelocatable.fromFelt(Felt252.fromInt(u8, 1).neg()));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        MathError.Felt252ToUsizeConversion,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element with empty scope" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try hint_processor.executeHint(
        std.testing.allocator,
        &setup.vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );
}

test "Find element with with number of elements greater than max size" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    try exec_scopes.assignOrUpdateVariable("find_element_max_size", .{ .felt = Felt252.one() });

    try expectError(
        HintError.FindElemMaxSize,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Find element with key not in integer" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("key", MaybeRelocatable.fromSegment(1, 4));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.FIND_ELEMENT, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Search sorted lower simple" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.SEARCH_SORTED_LOWER, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try hint_processor.executeHint(
        std.testing.allocator,
        &setup.vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 1),
        setup.vm.segments.memory.data.items[1].items[3].?.maybe_relocatable,
    );
}

test "Search sorted lower with no match" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("key", MaybeRelocatable.fromInt(u8, 7));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.SEARCH_SORTED_LOWER, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try hint_processor.executeHint(
        std.testing.allocator,
        &setup.vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );

    try expectEqual(
        MaybeRelocatable.fromInt(u8, 2),
        setup.vm.segments.memory.data.items[1].items[3].?.maybe_relocatable,
    );
}

test "Search sorted lower with not integer in element size" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("elm_size", MaybeRelocatable.fromSegment(7, 8));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.SEARCH_SORTED_LOWER, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Search sorted lower with zero element size" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("elm_size", MaybeRelocatable.fromFelt(Felt252.zero()));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.SEARCH_SORTED_LOWER, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.ValueOutsideValidRange,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Search sorted lower with not integer in number elements" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();
    try values_to_override.put("n_elms", MaybeRelocatable.fromSegment(2, 2));

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.SEARCH_SORTED_LOWER, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try expectError(
        HintError.IdentifierNotInteger,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}

test "Search sorted lower with empty scope" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.SEARCH_SORTED_LOWER, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try hint_processor.executeHint(
        std.testing.allocator,
        &setup.vm,
        &hint_data,
        undefined,
        &exec_scopes,
    );
}

test "Search sorted lower with number of elements greater than max size" {
    var values_to_override = std.StringHashMap(MaybeRelocatable).init(std.testing.allocator);
    defer values_to_override.deinit();

    var setup = try initVmIdsData(&values_to_override);
    defer setup.vm.deinit();
    defer setup.vm.segments.memory.deinitData(std.testing.allocator);
    defer setup.ids_data.deinit();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    var hint_data = HintData.init(hint_codes.SEARCH_SORTED_LOWER, setup.ids_data, .{});

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    try exec_scopes.assignOrUpdateVariable("find_element_max_size", .{ .felt = Felt252.one() });

    try expectError(
        HintError.FindElemMaxSize,
        hint_processor.executeHint(
            std.testing.allocator,
            &setup.vm,
            &hint_data,
            undefined,
            &exec_scopes,
        ),
    );
}
