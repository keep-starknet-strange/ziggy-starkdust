const std = @import("std");

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

pub fn HashMapWithArray(comptime K: type, V: type) type {
    return struct {
        const Self = @This();

        map: std.AutoHashMap(K, std.ArrayList(V)),

        pub fn init(allocator: Allocator) Self {
            return .{
                .map = std.AutoHashMap(K, std.ArrayList(V)).init(allocator),
            };
        }

        pub fn get(self: *Self, k: K) ?std.ArrayList(V) {
            return self.map.get(k);
        }

        pub fn put(self: *Self, k: K, v: std.ArrayList(V)) !void {
            try self.map.put(k, v);
        }

        pub fn deinit(self: *Self) void {
            var iterator = self.map.valueIterator();
            while (iterator.next()) |v| {
                v.deinit();
            }
            self.map.deinit();
        }
    };
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

    return hint_processor_utils.getPtrFromReference(reference, ap_tracking, vm) catch |err| {
        switch (err) {
            HintError.WrongIdentifierTypeInternal => return HintError.IdentifierNotRelocatable,
            else => return HintError.UnknownIdentifier,
        }
    };
}

pub fn getReferenceFromVarName(
    var_name: []const u8,
    ids_data: std.StringHashMap(HintReference),
) !HintReference {
    return if (ids_data.get(var_name)) |d| d else HintError.UnknownIdentifier;
}

//Gets the address, as a MaybeRelocatable of the variable given by the ids name
pub fn getAddressFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !MaybeRelocatable {
    return MaybeRelocatable.fromRelocatable(try getRelocatableFromVarName(var_name, vm, ids_data, ap_tracking));
}

//Gets the address, as a Relocatable of the variable given by the ids name
pub fn getRelocatableFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !Relocatable {
    return if (ids_data.get(var_name)) |x| if (hint_processor_utils.computeAddrFromReference(x, ap_tracking, vm)) |v| v else HintError.UnknownIdentifier else HintError.UnknownIdentifier;
}

//Gets the value of a variable name.
//If the value is an MaybeRelocatable::Int(Bigint) return &Bigint
//else raises Err
pub fn getIntegerFromVarName(
    var_name: []const u8,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !Felt252 {
    const reference = try getReferenceFromVarName(var_name, ids_data);

    return hint_processor_utils.getIntegerFromReference(vm, reference, ap_tracking) catch |err| switch (err) {
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
            const val = vm.segments.memory.get(address);
            if (val) |value| {
                return value;
            }
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
    return if (hint_processor_utils.getMaybeRelocatableFromReference(vm, reference, ap_tracking)) |v| v else HintError.UnknownIdentifier;
}

// pub fn getConstantFromVarName(
//     var_name: []const u8,
//     constants:  std.StringHashMap(Felt252),
// ) !Felt252 {
//     constants
//         .iter()
//         .find(|(k, _)| k.rsplit('.').next() == Some(var_name))
//         .map(|(_, n)| n)
//         .ok_or_else(|| HintError::MissingConstant(Box::new(var_name)))
// }
