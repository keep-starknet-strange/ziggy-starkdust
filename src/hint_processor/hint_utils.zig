const std = @import("std");

const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintReference = @import("./hint_processor_def.zig").HintReference;
const CoreVM = @import("../vm/core.zig");
const OffsetValue = @import("../vm/types/programjson.zig");
const CairoVM = CoreVM.CairoVM;
const relocatable = @import("../vm/memory/relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;

pub const IdsManager = struct {
    const Self = @This();

    References: std.AutoHashMap([]const u8, HintReference),
    HintApTracking: ApTracking,
    AccessibleScopes: []const []const u8,

    pub fn getFelt(self: *Self, name: []const u8, vm: *CairoVM) !Felt252 {
        const val = try self.get(name, vm);
        return try vm.getFelt(val);
    }

    pub fn get(self: *Self, name: []const u8, vm: *CairoVM) !?*MaybeRelocatable {
        if (self.References.get(name)) |reference| {
            if (getValueFromReference(reference, self.HintApTracking, vm)) |val| {
                return val;
            }
        }
        return error.ErrUnknownIdentifier;
    }
};

pub fn getValueFromReference(reference: *HintReference, ap_tracking: ApTracking, vm: *CairoVM) ?*MaybeRelocatable {
    // Handle the case of immediate
    if (@typeInfo(reference.offset1) == .immediate) {
        return MaybeRelocatable.fromFelt(Felt252.fromInt(reference.offset1.immediate));
    }
    if (getAddressFromReference(reference, ap_tracking, vm)) |address| {
        if (reference.dereference) {
            if (vm.segments.memory.get(address)) |value| {
                return value;
            }
        } else {
            return MaybeRelocatable.fromRelocatable(address);
        }
    }
    return null;
}

pub fn getAddressFromReference(reference: *HintReference, ap_tracking: ApTracking, vm: *CairoVM) !?Relocatable {
    if (@typeInfo(reference.offset1) != .reference) {
        return null;
    }
    const offset1 = getOffsetValueReference(reference.offset1, reference.ap_tracking_data, ap_tracking, vm) catch return null;
    if (offset1) |*offset1_rel| {
        switch (reference.offset2) {
            .reference => {
                const offset2 = getOffsetValueReference(reference.offset2, reference.ap_tracking_data, ap_tracking, vm) catch return null;
                if (offset2) |*offset2_val| {
                    return offset1_rel.AddMaybeRelocatable(offset2_val) catch null;
                }
            },
            .value => {
                return offset1_rel.AddInt(reference.offset2.Value) catch null;
            },
            else => {},
        }
    }
    return null;
}

pub fn getOffsetValueReference(offset_value: OffsetValue, ref_ap_tracking: ApTracking, hint_ap_tracking: ApTracking, vm: *CairoVM) ?*MaybeRelocatable {
    var base_addr: ?Relocatable = null;
    switch (offset_value.reference.Register) {
        .FP => base_addr = vm.run_context.fp,
        .AP => {
            if (applyApTrackingCorrection(vm.run_context.ap, ref_ap_tracking, hint_ap_tracking)) |addr| {
                base_addr = addr;
            } else return null;
        },
    }

    if (try base_addr.addUint(offset_value.value)) |addr| {
        if (offset_value.dereference) {
            if (vm.segments.memory.get(addr)) |value| {
                return value;
            }
        } else {
            return MaybeRelocatable.fromRelocatable(addr);
        }
    }

    return null;
}

pub fn applyApTrackingCorrection(addr: Relocatable, ref_ap_tracking: ApTracking, hint_ap_tracking: ApTracking) ?Relocatable {
    if (ref_ap_tracking.group == hint_ap_tracking.group) {
        return try addr.subUint(hint_ap_tracking.offset - ref_ap_tracking.offset);
    }
    return null;
}
