const std = @import("std");
const relocatable = @import("../vm/memory/relocatable.zig");

const CairoVM = @import("../vm/core.zig").CairoVM;
const MaybeRelocatable = relocatable.MaybeRelocatable;
const IdsManager = @import("hint_utils.zig").IdsManager;
const HintReference = @import("../hint_processor/hint_processor_def.zig").HintReference;

pub fn setupIdsForTest(allocator: std.mem.Allocator, data: []const struct { name: []const u8, elems: []const ?MaybeRelocatable }, vm: *CairoVM) !std.StringHashMap(HintReference) {
    var result = std.StringHashMap(HintReference).init(allocator);
    errdefer result.deinit();

    var current_offset: usize = 0;
    var base_addr = vm.run_context.getFP();

    for (data) |d| {
        try result.put(d.name, .{
            .dereference = true,
            .offset1 = .{
                .reference = .{ .FP, @intCast(current_offset), false },
            },
        });
        // update current offset
        current_offset = current_offset + d.elems.len;

        // Insert ids variables
        for (d.elems, 0..) |elem, n| {
            if (elem) |val| {
                try vm.insertInMemory(
                    allocator,
                    try base_addr.addUint(n),
                    val,
                );
            }
        }

        // Update base_addr
        base_addr.offset = base_addr.offset + d.elems.len;
    }

    return result;
}
