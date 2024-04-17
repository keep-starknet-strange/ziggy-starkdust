const std = @import("std");
const hint_utils = @import("hint_utils.zig");
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;

pub fn sha256Input(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const nBytes = try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking);
    const value = if (nBytes.ge(Felt252.fromInt(u8, 4))) {
        Felt252.one();
    } else {
        Felt252.zero();
    };
    try hint_utils.insertValueFromVarName(allocator, "full_word", MaybeRelocatable.fromFelt(value), vm, ids_data, ap_tracking);
}

// pub fn sha256Main(allocator: std.mem.Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking, constants: std.StringHashMap(Felt252), iv: [8]u32) !void {
//     const inputPtr = try hint_utils.getPtrFromVarName("sha256_start", vm, ids_data, ap_tracking);
//     const inputChunkSizeFelts = try hint_utils.getConstantFromVarName(var_name: []const u8, constants: *const std.StringHashMap(Felt252))
// }
