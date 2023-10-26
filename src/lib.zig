pub const vm = struct {
    pub usingnamespace @import("vm/core.zig");
    pub usingnamespace @import("vm/config.zig");
    pub usingnamespace @import("vm/error.zig");
    pub usingnamespace @import("vm/instructions.zig");
    pub usingnamespace @import("vm/run_context.zig");
    pub usingnamespace @import("vm/memory/memory.zig");
    pub usingnamespace @import("vm/memory/relocatable.zig");
    pub usingnamespace @import("vm/memory/segments.zig");
};

pub const math = struct {
    pub usingnamespace @import("math/fields/fields.zig");
    pub usingnamespace @import("math/fields/stark_felt_252_gen_fp.zig");
    pub usingnamespace @import("math/fields/starknet.zig");
};

pub const utils = struct {
    pub usingnamespace @import("utils/log.zig");
    pub usingnamespace @import("utils/time.zig");
};
