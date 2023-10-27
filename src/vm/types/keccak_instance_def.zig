const std = @import("std");

const ArrayList = std.ArrayList;

pub const KeccakInstanceDef = struct {
    const Self = @This();

    ratio: ?u32,
    _state_rep: ArrayList(u32),
    _instance_per_component: u32,

    pub fn cells_per_builtin(self: *Self) u32 {
        return 2 * @as(u32, self._state_rep.items.len);
    }
};
