const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expect = std.testing.expect;
const hint_utils = @import("hint_utils.zig");
const testing_utils = @import("testing_utils.zig");

const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const Allocator = std.mem.Allocator;
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintError = @import("../vm/error.zig").HintError;
const vm_error = @import("../vm/error.zig");
const RangeCheckBuiltinRunner = @import("../vm/builtins/builtin_runner/range_check.zig").RangeCheckBuiltinRunner;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const HintData = @import("hint_processor_def.zig").HintData;
const hint_codes = @import("builtin_hint_codes.zig");

/// Implements the hint: `ids.locs.bit = (ids.prev_locs.exp % PRIME) & 1`
///
/// This function calculates the value of `ids.locs.bit` based on the previous locations (`ids.prev_locs.exp`) modulo PRIME,
/// and then performs a bitwise AND operation with 1.
///
/// # Parameters
/// - `allocator`: Allocator to manage memory allocation.
/// - `vm`: Pointer to the CairoVM instance.
/// - `ids_datas`: HashMap containing hint references.
/// - `ap_tracking`: ApTracking instance for tracking applied hints.
///
/// # Returns
/// This function returns `void` if successful.
/// If an error occurs during hint processing, it returns `HintError.IdentifierHasNoMember`.
pub fn pow(
    allocator: Allocator,
    vm: *CairoVM,
    ids_datas: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Get the previous locations exponent
    const prev_locs_exp = vm.getFelt(
        try (try hint_utils.getRelocatableFromVarName(
            "prev_locs",
            vm,
            ids_datas,
            ap_tracking,
        )).addUint(4),
    ) catch return HintError.IdentifierHasNoMember;

    // Calculate the value of ids.locs.bit
    try hint_utils.insertValueFromVarName(
        allocator,
        "locs",
        MaybeRelocatable.fromFelt((try prev_locs_exp.divRem(Felt252.two()))[1]),
        vm,
        ids_datas,
        ap_tracking,
    );
}

test "PowUtils: run pow" {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Append the RangeCheckBuiltinRunner to the list of builtin runners.
    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    // Set the value of vm.run_context.fp to Relocatable(1, 12).
    vm.run_context.fp = 12;

    // Set up memory segments for the Cairo VM.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 1, 11 }, .{3} }},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Add variable references for "prev_locs" and "locs" to the hashmap.
    try ids_data.put("prev_locs", HintReference.initSimple(-5));
    try ids_data.put("locs", HintReference.initSimple(0));

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the POW hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.POW, ids_data, .{});

    // Execute the hint processor with the provided data.
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // Verify that the value at memory location [1][12] is equal to 1.
    try expectEqual(
        MaybeRelocatable.fromInt(u8, 1),
        vm.segments.memory.data.items[1].items[12].?.maybe_relocatable,
    );
}

test "PowUtils: with incorrect ids" {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Append the RangeCheckBuiltinRunner to the list of builtin runners.
    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    // Add two memory segments to the Cairo VM.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Set the value of vm.run_context.ap to Relocatable(1, 11).
    vm.run_context.ap = 11;

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Add a variable reference for "locs" to the hashmap.
    try ids_data.put("locs", HintReference.initSimple(-1));

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the POW hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.POW, ids_data, .{});

    // Execute the hint processor with the provided data and expect an error.
    try expectError(
        HintError.UnknownIdentifier,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "PowUtils: with incorrect references" {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Append the RangeCheckBuiltinRunner to the list of builtin runners.
    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    // Add two memory segments to the Cairo VM.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Set the value of vm.run_context.ap to Relocatable(1, 11).
    vm.run_context.ap = 11;

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Add variable references for "prev_locs" and "locs" to the hashmap.
    try ids_data.put("prev_locs", HintReference.initSimple(-5));
    try ids_data.put("locs", HintReference.initSimple(-12));

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the POW hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.POW, ids_data, .{});

    // Execute the hint processor with the provided data and expect an error.
    try expectError(
        HintError.UnknownIdentifier,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "PowUtils: with exponent not being an integer" {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Append the RangeCheckBuiltinRunner to the list of builtin runners.
    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    // Set the value of vm.run_context.ap to Relocatable(1, 11).
    vm.run_context.ap = 11;

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Add variable references for "prev_locs" and "locs" to the hashmap.
    try ids_data.put("prev_locs", HintReference.initSimple(-5));
    try ids_data.put("locs", HintReference.initSimple(-12));

    // Insert ids.prev_locs.exp into memory as a RelocatableValue (not an integer).
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 1, 10 }, .{ 1, 11 } }},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Add one memory segment to the Cairo VM.
    inline for (0..1) |_| _ = try vm.addMemorySegment();

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the POW hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.POW, ids_data, .{});

    // Execute the hint processor with the provided data and expect an error.
    try expectError(
        HintError.UnknownIdentifier,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}

test "PowUtils: with invalid memory inserted" {
    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Append the RangeCheckBuiltinRunner to the list of builtin runners.
    try vm.builtin_runners.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) });

    // Set the value of vm.run_context.ap to Relocatable(1, 11).
    vm.run_context.ap = 11;

    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Add variable references for "prev_locs" and "locs" to the hashmap.
    try ids_data.put("prev_locs", HintReference.initSimple(-5));
    try ids_data.put("locs", HintReference.initSimple(0));

    // Insert ids.prev_locs.exp into memory as a RelocatableValue (not an integer).
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 10 }, .{3} },
            .{ .{ 1, 11 }, .{3} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the POW hint code and the ids_data hashmap.
    var hint_data = HintData.init(hint_codes.POW, ids_data, .{});

    // Execute the hint processor with the provided data and expect an error.
    try expectError(
        HintError.UnknownIdentifier,
        hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined),
    );
}
