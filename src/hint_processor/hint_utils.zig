const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const Register = @import("../vm/instructions.zig").Register;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintReference = @import("hint_processor_def.zig").HintReference;
const CoreVM = @import("../vm/core.zig");
const OffsetValue = @import("../vm/types/programjson.zig").OffsetValue;
const CairoVM = CoreVM.CairoVM;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const Allocator = std.mem.Allocator;
const HintError = @import("../vm/error.zig").HintError;
const hint_processor_utils = @import("hint_processor_utils.zig");

pub fn getConstantFromVarName(
    var_name: []const u8,
    constants: *const std.StringHashMap(Felt252),
) !Felt252 {
    var it = constants.iterator();
    while (it.next()) |k| {
        if (k.key_ptr.*.len < var_name.len) continue;
        if (std.mem.eql(u8, var_name, k.key_ptr.*[k.key_ptr.*.len - var_name.len ..]))
            return k.value_ptr.*;
    }

    return HintError.MissingConstant;
}

//Inserts value into the address of the given ids variable
pub fn insertValueFromVarName(
    allocator: Allocator,
    var_name: []const u8,
    value: MaybeRelocatable,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const var_address = try getRelocatableFromVarName(var_name, vm, ids_data, ap_tracking);
    try vm.segments.memory.set(allocator, var_address, value);
}

//Inserts value into ap
pub fn insertValueIntoAp(
    allocator: Allocator,
    vm: *CairoVM,
    value: MaybeRelocatable,
) !void {
    try vm.segments.memory.set(allocator, vm.run_context.getAP(), value);
}

//Returns the Relocatable value stored in the given ids variable
pub fn getPtrFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !Relocatable {
    const reference = try getReferenceFromVarName(var_name, ids_data);

    return hint_processor_utils.getPtrFromReference(reference, ap_tracking, vm) catch |err|
        switch (err) {
        HintError.WrongIdentifierTypeInternal => HintError.IdentifierNotRelocatable,
        else => HintError.UnknownIdentifier,
    };
}

pub fn getReferenceFromVarName(
    var_name: []const u8,
    ids_data: std.StringHashMap(HintReference),
) !HintReference {
    return ids_data.get(var_name) orelse HintError.UnknownIdentifier;
}

//Gets the address, as a MaybeRelocatable of the variable given by the ids name
pub fn getAddressFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !MaybeRelocatable {
    return MaybeRelocatable.fromRelocatable(
        try getRelocatableFromVarName(
            var_name,
            vm,
            ids_data,
            ap_tracking,
        ),
    );
}

//Gets the address, as a Relocatable of the variable given by the ids name
pub fn getRelocatableFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !Relocatable {
    return if (ids_data.get(var_name)) |x|
        if (hint_processor_utils.computeAddrFromReference(x, ap_tracking, vm)) |v|
            v
        else
            HintError.UnknownIdentifier
    else
        HintError.UnknownIdentifier;
}

/// Retrieves the value of a variable by its name.
///
/// This function retrieves the value of a variable identified by its name. If the value is an
/// integer, it returns the integer value. Otherwise, it raises an error.
///
/// # Parameters
/// - `var_name`: The name of the variable to retrieve.
/// - `vm`: Pointer to the Cairo virtual machine.
/// - `ids_data`: String hashmap containing variable references.
/// - `ap_tracking`: ApTracking object representing the current activation packet tracking.
///
/// # Returns
/// Returns the integer value of the variable identified by `var_name`.
///
/// # Errors
/// Returns an error if the variable value is not an integer or if the variable is not found.
pub fn getIntegerFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !Felt252 {
    // Retrieve the reference to the variable using its name.
    const reference = try getReferenceFromVarName(var_name, ids_data);

    // Get the integer value from the reference.
    return hint_processor_utils.getIntegerFromReference(vm, reference, ap_tracking) catch |err|
    // Handle specific errors.
        switch (err) {
        HintError.WrongIdentifierTypeInternal => HintError.IdentifierNotInteger,
        else => HintError.UnknownIdentifier,
    };
}

pub fn getValueFromReference(reference: HintReference, ap_tracking: ApTracking, vm: *CairoVM) !?MaybeRelocatable {
    // Handle the case of immediate
    switch (reference.offset1) {
        .immediate => |val| return MaybeRelocatable.fromFelt(val),
        else => {},
    }

    if (try hint_processor_utils.getPtrFromReference(reference, ap_tracking, vm)) |address| {
        if (reference.dereference) {
            return vm.segments.memory.get(address);
        } else {
            return MaybeRelocatable.fromRelocatable(address);
        }
    }

    return null;
}

//Gets the value of a variable name as a MaybeRelocatable
pub fn getMaybeRelocatableFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !MaybeRelocatable {
    const reference = try getReferenceFromVarName(var_name, ids_data);

    return hint_processor_utils.getMaybeRelocatableFromReference(vm, reference, ap_tracking) orelse HintError.UnknownIdentifier;
}

test "getIntegerFromVarName: valid" {
    // Initializes the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit(); // Ensure cleanup.

    // Sets up memory segments in the virtual machine.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 1, 0 }, .{1} }},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator); // Clean up memory data.

    // Creates a hashmap containing variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Puts a hint reference named "value" into the hashmap.
    try ids_data.put("value", HintReference.initSimple(0));

    // Calls `getIntegerFromVarName` function with the variable name "value".
    try expectEqual(
        Felt252.fromInt(u8, 1),
        try getIntegerFromVarName("value", &vm, ids_data, .{}),
    );
}

test "getIntegerFromVarName: invalid" {
    // Initializes the Cairo virtual machine.
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit(); // Ensure cleanup.

    // Sets up memory segments in the virtual machine with an invalid configuration.
    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{.{ .{ 1, 0 }, .{ 0, 0 } }},
    );
    defer vm.segments.memory.deinitData(std.testing.allocator); // Clean up memory data.

    // Creates a hashmap containing variable references.
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    // Puts a hint reference named "value" into the hashmap.
    try ids_data.put("value", HintReference.initSimple(0));

    // Calls `getIntegerFromVarName` function with the variable name "value".
    // Expects the function to return an error of type `HintError.IdentifierNotInteger`.
    try expectError(
        HintError.IdentifierNotInteger,
        getIntegerFromVarName("value", &vm, ids_data, .{}),
    );
}
