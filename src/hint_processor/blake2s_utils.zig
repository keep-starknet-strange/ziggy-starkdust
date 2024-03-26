const hint_utils = @import("hint_utils.zig");
const std = @import("std");
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const testing_utils = @import("testing_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const hint_codes = @import("builtin_hint_codes.zig");
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintData = @import("hint_processor_def.zig").HintData;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const HintType = @import("../vm/types/execution_scopes.zig").HintType;
const Allocator = std.mem.Allocator;
const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;
const MemoryError = @import("../vm/error.zig").MemoryError;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
fn getFixedSizeU32Array(comptime T: usize, h_range: std.ArrayList(Felt252)) ![T]u32 {
    var result = [T]u32{};
    for (h_range.items, 0..T) |h, i| {
        const temp = try @as(u32, h.toInteger());
        result[i] = temp;
    }
}

fn computeBlake2sFunc(_: Allocator, vm: *CairoVM, output_ptr: Relocatable) !void {
    const h = try getFixedSizeU32Array(8, try vm.getFeltRange(try output_ptr.subUint(26), 8));
    const message = try getFixedSizeU32Array(16, try vm.getFeltRange(try output_ptr.subUint(18), 16));
    const t = try @as(u32, try output_ptr.subUint(2));
    const f = try @as(u32, try output_ptr.subUint(1));
}

pub fn computeBlake2s(_: Allocator, vm: *CairoVM, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) !void {
    var output = try hint_utils.getPtrFromVarName("output", vm, ids_data, ap_tracking);
}
