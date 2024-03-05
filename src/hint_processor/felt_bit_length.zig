const std = @import("std");
const Allocator = std.mem.Allocator;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

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

/// Implements a hint that calculates the bit length of a variable and assigns it to another variable.
///
/// This function retrieves the value of variable `x` from the provided `ids_datas`, calculates its bit length,
/// and then inserts the bit length value into the `ids_datas` under the variable name `bit_length`.
///
/// # Arguments
///
/// - `allocator`: An allocator to manage memory allocation.
/// - `vm`: A pointer to the CairoVM instance.
/// - `ids_datas`: A hashmap containing variable names and their associated references.
/// - `ap_tracking`: An ApTracking instance providing access path tracking information.
///
/// # Errors
///
/// This function returns an error if there is any issue with retrieving or inserting values into the `ids_datas`.
///
/// # Implements hint:
/// ```python
/// x = ids.x,
/// ids.bit_length = x.bit_length()
/// ```
pub fn getFeltBitLength(
    allocator: Allocator,
    vm: *CairoVM,
    ids_datas: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Retrieve the value of variable `x` from `ids_datas`.
    const x = try hint_utils.getIntegerFromVarName("x", vm, ids_datas, ap_tracking);

    // Calculate the bit length of `x`.
    // Insert the bit length value into `ids_datas` under the variable name `bit_length`.
    try hint_utils.insertValueFromVarName(
        allocator,
        "bit_length",
        MaybeRelocatable.fromInt(usize, x.numBits()),
        vm,
        ids_datas,
        ap_tracking,
    );
}

test "FeltBitLength: simple test" {
    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Store references for variables "x" and "bit_length".
    // Variable "x" is located at `fp + 0`, and "bit_length" at `fp + 1`.
    try ids_data.put("x", HintReference.initSimple(0));
    try ids_data.put("bit_length", HintReference.initSimple(1));

    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Set the frame pointer to point to the beginning of the stack.
    vm.run_context.*.fp.* = .{};

    // Allocate memory space for variables `ids.x` and `ids.bit_length`.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Set up memory segments in the virtual machine.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 0, 0 }, .{7} }},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the GET_FELT_BIT_LENGTH hint code and the `ids_data`.
    var hint_data = HintData.init(hint_codes.GET_FELT_BIT_LENGTH, ids_data, .{});

    // Execute the hint processor with the provided data.
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // Retrieve the result from the memory location of `ids.bit_length`.
    const res = try vm.getFelt(Relocatable.init(0, 1));

    // Ensure that the result matches the expected value.
    try expectEqual(Felt252.fromInt(u8, 3), res);
}

test "FeltBitLength: range test" {
    // Iterate over a range of values from 0 to 251 (inclusive).
    for (0..252) |i| {
        // Initialize a hashmap to store variable references.
        var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
        defer ids_data.deinit();

        // Store references for variables "x" and "bit_length".
        // Variable "x" is located at `fp + 0`, and "bit_length" at `fp + 1`.
        try ids_data.put("x", HintReference.initSimple(0));
        try ids_data.put("bit_length", HintReference.initSimple(1));

        // Initialize the Cairo virtual machine.
        var vm = try CairoVM.init(std.testing.allocator, .{});
        defer vm.deinit();

        // Set the frame pointer to point to the beginning of the stack.
        vm.run_context.*.fp.* = .{};

        // Allocate memory space for variables `ids.x` and `ids.bit_length`.
        inline for (0..2) |_| _ = try vm.addMemorySegment();

        // Set the value of `ids.x` to 2^i.
        try vm.segments.memory.set(
            std.testing.allocator,
            .{},
            MaybeRelocatable.fromFelt(Felt252.two().pow(i)),
        );
        defer vm.segments.memory.deinitData(std.testing.allocator);

        // Initialize a HintProcessor instance.
        const hint_processor: HintProcessor = .{};

        // Initialize HintData with the GET_FELT_BIT_LENGTH hint code and the `ids_data`.
        var hint_data = HintData.init(hint_codes.GET_FELT_BIT_LENGTH, ids_data, .{});

        // Execute the hint processor with the provided data.
        try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

        // Retrieve the result from the memory location of `ids.bit_length`.
        const res = try vm.getFelt(Relocatable.init(0, 1));

        // Ensure that the result matches the expected value.
        try expectEqual(Felt252.fromInt(u256, i + 1), res);
    }
}

test "FeltBitLength: wrap around" {
    // Initialize a hashmap to store variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Store references for variables "x" and "bit_length".
    // Variable "x" is located at `fp + 0`, and "bit_length" at `fp + 1`.
    try ids_data.put("x", HintReference.initSimple(0));
    try ids_data.put("bit_length", HintReference.initSimple(1));

    // Initialize the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();

    // Set the frame pointer to point to the beginning of the stack.
    vm.run_context.*.fp.* = .{};

    // Allocate memory space for variables `ids.x` and `ids.bit_length`.
    inline for (0..2) |_| _ = try vm.addMemorySegment();

    // Set the value of `ids.x` to (Felt252.Modulo - 1) + 1, causing wrap around.
    try vm.segments.memory.set(
        std.testing.allocator,
        .{},
        MaybeRelocatable.fromFelt(
            Felt252.fromInt(u256, Felt252.Modulo - 1).add(Felt252.one()),
        ),
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Initialize a HintProcessor instance.
    const hint_processor: HintProcessor = .{};

    // Initialize HintData with the GET_FELT_BIT_LENGTH hint code and the `ids_data`.
    var hint_data = HintData.init(hint_codes.GET_FELT_BIT_LENGTH, ids_data, .{});

    // Execute the hint processor with the provided data.
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // Retrieve the result from the memory location of `ids.bit_length`.
    const res = try vm.getFelt(Relocatable.init(0, 1));

    // Ensure that the result matches the expected value (0).
    try expectEqual(Felt252.zero(), res);
}
