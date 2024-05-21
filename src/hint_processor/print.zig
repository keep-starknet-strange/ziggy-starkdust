const std = @import("std");
const Allocator = std.mem.Allocator;
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const hint_utils = @import("hint_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const HintError = @import("../vm/error.zig").HintError;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const dict_manager = @import("../hint_processor/dict_manager.zig");

pub fn printFelt(_: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const val = try hint_utils.getIntegerFromVarName("x", vm, ids_data, ap_tracking);
    std.log.err("{}\n", .{val.toU256()});
}

pub fn printName(_: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    const name = try hint_utils.getIntegerFromVarName("name", vm, ids_data, ap_tracking);
    std.debug.print("{}\n", .{name});
}

pub fn printArray(allocator: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    try printName(allocator, vm, ids_data, ap_tracking);
    const arr = try hint_utils.getPtrFromVarName("arr", vm, ids_data, ap_tracking);
    const temp = try hint_utils.getIntegerFromVarName("arr_len", vm, ids_data, ap_tracking);
    const arr_len = try temp.toInt(usize);

    var acc = try allocator.alloc(Felt252, arr_len);
    defer allocator.free(acc);
    for (0..arr_len) |i| {
        const val = try vm.getFelt(try arr.addUint(@as(u64, i)));
        acc[i] = val;
    }
    std.debug.print("arr: {any}\n", .{acc});
}
const DictValue = union {
    felt: Felt252,
    relocatable: []Felt252,
};

pub fn printDict(allocator: Allocator, vm: *CairoVM, exec_scopes: *ExecutionScopes, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    try printName(allocator, vm, ids_data, ap_tracking);
    const dict_ptr = try hint_utils.getPtrFromVarName("dict_ptr", vm, ids_data, ap_tracking);
    const pointer_size_felt = try hint_utils.getIntegerFromVarName("pointer_size", vm, ids_data, ap_tracking);
    const pointer_size = try pointer_size_felt.toInt(usize);
    if (pointer_size < 0) {
        return error.HintError("pointer_size is negative");
    }

    var dict_rc = try exec_scopes.getDictManager();
    defer dict_rc.releaseWithFn(dict_manager.DictManager.deinit);

    const tracker = try dict_rc.value.getTrackerRef(dict_ptr);
    var map: std.AutoHashMap(MaybeRelocatable, MaybeRelocatable) = switch (tracker.data) {
        .SimpleDictionary => |dict| dict,
        .DefaultDictionary => |dict| dict.dict,
    };

    var acc = std.AutoHashMap(Felt252, DictValue).init(allocator);
    defer acc.deinit();
    var it = map.iterator();
    while (it.next()) |el| {
        const key = try el.key_ptr.intoFelt();
        const val = el.value_ptr.*;
        switch (val) {
            .felt => |felt| try acc.put(key, DictValue{ .felt = felt }),
            .relocatable => |relocatable| {
                var structure = try allocator.alloc(Felt252, pointer_size);
                defer allocator.free(structure);
                for (0..pointer_size) |i| {
                    structure[i] = try vm.getFelt(try relocatable.addUint(@as(u64, i)));
                }
                try acc.put(key, DictValue{ .relocatable = structure });
            },
        }
    }
    std.debug.print("dict: {any}\n", .{acc});
}
