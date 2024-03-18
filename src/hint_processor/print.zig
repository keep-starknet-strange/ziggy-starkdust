const std = @import("std");
const Allocator = std.mem.Allocator;
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const hint_utils = @import("hint_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintError = @import("../vm/error.zig").HintError;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;

pub fn printFelt(_: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const val = try hint_utils.getIntegerFromVarName("x", vm, ids_data, ap_tracking);
    std.debug.print("{}\n", .{val});
}

pub fn printName(_: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const name = try hint_utils.getIntegerFromVarName("name", vm, ids_data, ap_tracking);
    std.debug.print("{}\n", .{name});
}

pub fn printArray(allocator: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    try printName(allocator, vm, ids_data, ap_tracking);
    const arr = try hint_utils.getPtrFromVarName("arr", vm, ids_data, ap_tracking);
    const temp = try hint_utils.getIntegerFromVarName("arr_len", vm, ids_data, ap_tracking);
    const arr_len = try temp.intoUsize();
    var acc = try allocator.alloc(Felt252, arr_len);
    defer allocator.free(acc);
    for (0..arr_len) |i| {
        const val = try vm.getFelt(try arr.addUint(@as(u64, i)));
        acc[i] = val;
    }
    std.debug.print("arr: {any}\n", .{acc});
}
