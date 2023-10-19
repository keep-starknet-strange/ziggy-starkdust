pub const vm = struct {
    pub usingnamespace @import("vm/core.zig");
    pub usingnamespace @import("vm/instructions.zig");
    pub usingnamespace @import("vm/run_context.zig");
};
