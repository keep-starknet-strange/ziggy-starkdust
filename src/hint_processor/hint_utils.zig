const std = @import("std");

const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintReference = @import("hint_processor_def.zig").HintReference;
const CoreVM = @import("../vm/core.zig");
const OffsetValue = @import("../vm/types/programjson.zig");
const CairoVM = CoreVM.CairoVM;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const Allocator = std.mem.Allocator;

pub const IdsManager = struct {
    const Self = @This();

    reference: std.AutoHashMap([]const u8, HintReference),
    hint_ap_tracking: ApTracking,
    accessible_scopes: []const []const u8,

    pub fn init(allocator: Allocator, hint_ap_tracking: ApTracking, accessible_scopes: []const []const u8) !*Self {
        return .{
            .reference = std.AutoHashMap([]const u8, HintReference).init(allocator),
            .hint_ap_tracking = hint_ap_tracking,
            .acessible_scopes = accessible_scopes,
        };
    }

    pub fn deinit(self: *Self) void {
        self.reference.deinit();
    }

    pub fn getFelt(self: *Self, name: []const u8, vm: *CairoVM) !Felt252 {
        const val = try self.get(name, vm);
        const felt = try vm.getFelt(val);
        return felt;
    }

    pub fn get(self: *Self, name: []const u8, vm: *CairoVM) !?*MaybeRelocatable {
        if (self.References.get(name)) |reference| {
            if (getValueFromReference(reference, self.HintApTracking, vm)) |val| {
                return val;
            }
        }
        return error.ErrUnknownIdentifier;
    }

    /// Insert a value into the memory of the VM at the address of the given name.
    pub fn insert(self: *Self, allocator: Allocator, name: []const u8, value: MaybeRelocatable, vm: *CairoVM) !void {
        const addr = try self.getAddr(name, value);

        try vm.segments.memory.set(allocator, addr, value);
    }

    pub fn getAddr(self: *Self, name: []const u8, vm: *CairoVM) !Relocatable {
        if (self.References.get(name)) |reference| {
            return getAddressFromReference(reference, self.HintApTracking, vm);
        }

        return error.ErrUnknownIdentifier;
    }
};

pub fn getValueFromReference(reference: *HintReference, ap_tracking: ApTracking, vm: *CairoVM) ?*MaybeRelocatable {
    // Handle the case of immediate
    if (@typeInfo(reference.offset1) == .immediate) {
        return MaybeRelocatable.fromFelt(Felt252.fromInt(reference.offset1.immediate));
    }
    const addr = getAddressFromReference(reference, ap_tracking, vm);
    if (addr) |address| {
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
                    const res = offset1_rel.AddMaybeRelocatable(offset2_val) catch return null;
                    return res;
                }
            },
            .value => {
                const res = offset1_rel.AddInt(reference.offset2.Value) catch return null;
                return res;
            },
            else => {},
        }
    }
    return null;
}

pub fn getOffsetValueReference(offset_value: OffsetValue, ref_ap_tracking: ApTracking, hint_ap_tracking: ApTracking, vm: *CairoVM) ?*MaybeRelocatable {
    var base_addr: Relocatable = undefined;
    var ok: bool = true;
    switch (offset_value.reference.Register) {
        .FP => base_addr = vm.run_context.fp,
        .AP => {
            const res = applyApTrackingCorrection(vm.run_context.ap, ref_ap_tracking, hint_ap_tracking);
            if (res) |addr| {
                base_addr = addr;
            } else {
                ok = false;
            }
        },
    }
    if (ok) {
        const res = try base_addr.addUint(offset_value.value);
        if (res) |addr| {
            if (offset_value.dereference) {
                const val = vm.segments.memory.get(addr);
                if (val) |value| {
                    return value;
                }
            } else {
                return MaybeRelocatable.fromRelocatable(addr);
            }
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
