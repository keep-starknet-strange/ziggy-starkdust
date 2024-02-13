const std = @import("std");
const relocatable = @import("../vm/memory/relocatable.zig");

const CairoVM = @import("../vm/core.zig").CairoVM;
const MaybeRelocatable = relocatable.MaybeRelocatable;
const IdsManager = @import("/hint_utils.zig").IdsManager;
const HintReference = @import("../hint_processor/hint_processor_def.zig").HintReference;

pub fn setupIdsForTest(allocator: std.mem.Allocator, data: []struct { name: []const u8, elems: []?MaybeRelocatable }, vm: *CairoVM) !IdsManager {
    var manager = try IdsManager.init(allocator, .{}, .{});
    errdefer manager.deinit();

    var current_offset = 0;
    var base_addr = vm.run_context.fp;

    for (data) |d| {
        try manager.reference.put(d.name, HintReference.init(current_offset, 0, false, true));
        // update current offset
        current_offset = current_offset + d.elems.len;

        // Insert ids variables
        for (d.elems, 0..) |elem, n| {
            if (elem) |val| {
                try vm.segments.memory.set(
                    allocator,
                    base_addr.addUint(n),
                    val,
                );
            }
        }

        // Update base_addr
        base_addr.offset = base_addr.offset + d.elems.len;
    }

    return manager;
}
