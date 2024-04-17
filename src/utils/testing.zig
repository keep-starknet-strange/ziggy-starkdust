const std = @import("std");
const Allocator = std.mem.Allocator;

const MemorySegmentManager = @import("../vm/memory/segments.zig").MemorySegmentManager;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const Memory = @import("../vm/memory/memory.zig").Memory;
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

pub const Cell = struct { address: Relocatable, value: MaybeRelocatable };

pub fn check_memory(memory: *Memory, cells: std.ArrayList(Cell)) bool {
    for (cells.items) |cell| {
        const check = check_memory_address(memory, cell.address, cell.value);
        if (!check) {
            return check;
        }
    }
    return true;
}

pub fn check_memory_address(memory: *Memory, address: Relocatable, expected_value: MaybeRelocatable) bool {
    const maybe_value = memory.get(address);
    if (maybe_value) |value| {
        return expected_value.eq(value);
    } else {
        return false;
    }
}
