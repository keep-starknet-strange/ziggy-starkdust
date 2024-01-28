const std = @import("std");
const Allocator = std.mem.Allocator;

const MemorySegmentManager = @import("../vm/memory/segments.zig").MemorySegmentManager;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MemoryCell = @import("../vm/memory/memory.zig").MemoryCell;

pub fn insertAtIndex(memory_manager: *MemorySegmentManager, allocator: Allocator, address: Relocatable, value: MaybeRelocatable) !void {
    var data = if (address.segment_index < 0) &memory_manager.memory.temp_data else &memory_manager.memory.data;
    const insert_segment_index: usize = @intCast(if (address.segment_index < 0) -(address.segment_index + 1) else address.segment_index);
    if (insert_segment_index >= data.items.len) {
        try data.appendNTimes(
            std.ArrayListUnmanaged(?MemoryCell){},
            insert_segment_index + 1 - data.items.len,
        );
    }

    try memory_manager.memory.set(allocator, address, value);
}
