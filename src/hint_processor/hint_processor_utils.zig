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

///Inserts value into the address of the given ids variable
pub fn insertValueFromReference(
    allocator: Allocator,
    value: MaybeRelocatable,
    vm: *CairoVM,
    hint_reference: HintReference,
    ap_tracking: ApTracking,
) !void {
    if (computeAddrFromReference(hint_reference, ap_tracking, vm)) |var_addr| {
        vm.segments.memory.set(allocator, var_addr, value) catch HintError.Memory;
    } else return HintError.UnknownIdentifierInternal;
}

///Returns the Integer value stored in the given ids variable
/// Returns an internal error, users should map it into a more informative type
pub fn getIntegerFromReference(
    vm: *CairoVM,
    hint_reference: HintReference,
    ap_tracking: ApTracking,
) !Felt252 {
    // if the reference register is none, this means it is an immediate value and we
    // should return that value.
    switch (hint_reference.offset1) {
        .immediate => |int_1| return int_1,
        else => {},
    }

    return if (computeAddrFromReference(hint_reference, ap_tracking, vm)) |var_addr| vm.segments.memory.getFelt(var_addr) catch HintError.WrongIdentifierTypeInternal else HintError.UnknownIdentifierInternal;
}

///Returns the Relocatable value stored in the given ids variable
pub fn getPtrFromReference(hint_reference: HintReference, ap_tracking: ApTracking, vm: *CairoVM) !Relocatable {
    const var_addr = computeAddrFromReference(hint_reference, ap_tracking, vm) orelse return HintError.UnknownIdentifierInternal;

    return if (hint_reference.dereference)
        vm.getRelocatable(var_addr) catch HintError.WrongIdentifierTypeInternal
    else
        var_addr;
}

pub fn applyApTrackingCorrection(addr: Relocatable, ref_ap_tracking: ApTracking, hint_ap_tracking: ApTracking) ?Relocatable {
    if (ref_ap_tracking.group == hint_ap_tracking.group) {
        return addr.subUint(hint_ap_tracking.offset - ref_ap_tracking.offset) catch unreachable;
    }
    return null;
}

pub fn getOffsetValueReference(
    vm: *CairoVM,
    hint_reference: HintReference,
    hint_ap_tracking: ApTracking,
    offset_value: OffsetValue,
) ?MaybeRelocatable {
    const refer = switch (offset_value) {
        .reference => |ref| ref,
        else => return null,
    };

    const base_addr = switch (refer[0]) {
        .FP => vm.run_context.fp.*,
        else => applyApTrackingCorrection(vm.run_context.getAP(), hint_reference.ap_tracking_data.?, hint_ap_tracking).?,
    };

    if (refer[1] < 0 and base_addr.offset < @as(u64, @intCast(@abs(refer[1])))) {
        return null;
    }

    if (refer[2]) {
        return vm.segments.memory.get(base_addr.addInt(@as(i64, @intCast(refer[1]))) catch unreachable).?;
    } else {
        return MaybeRelocatable.fromRelocatable(base_addr.addInt(@as(i64, @intCast(refer[1]))) catch unreachable);
    }
}
///Computes the memory address of the ids variable indicated by the HintReference as a [Relocatable]
pub fn computeAddrFromReference(hint_reference: HintReference, hint_ap_tracking: ApTracking, vm: *CairoVM) ?Relocatable {
    const offset1 = switch (hint_reference.offset1) {
        .reference => getOffsetValueReference(vm, hint_reference, hint_ap_tracking, hint_reference.offset1).?.tryIntoRelocatable() catch unreachable,
        else => return null,
    };

    return switch (hint_reference.offset2) {
        .reference => offset1.addFelt(getOffsetValueReference(vm, hint_reference, hint_ap_tracking, hint_reference.offset2).?.tryIntoFelt() catch unreachable) catch unreachable,

        .value => |val| offset1.addInt(val) catch unreachable,

        else => null,
    };
}

///Returns the value given by a reference as [MaybeRelocatable]
pub fn getMaybeRelocatableFromReference(
    vm: *CairoVM,
    hint_reference: HintReference,
    ap_tracking: ApTracking,
) ?MaybeRelocatable {
    //First handle case on only immediate
    switch (hint_reference.offset1) {
        .immediate => |num| return MaybeRelocatable.fromFelt(num),
        else => {},
    }

    //Then calculate address
    return if (computeAddrFromReference(hint_reference, ap_tracking, vm)) |var_addr|
        if (hint_reference.dereference)
            vm.segments.memory.get(var_addr)
        else
            MaybeRelocatable.fromRelocatable(var_addr)
    else
        null;
}
