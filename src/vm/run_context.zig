// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Local imports.
const Relocatable = @import("memory/relocatable.zig").Relocatable;

// Contains the register states of the Cairo VM.
pub const RunContext = struct {
    pc: *Relocatable,
    ap: *Relocatable,
    fp: *Relocatable,

    pub fn new(allocator: Allocator) !RunContext {
        var pc = allocator.create(Relocatable) catch unreachable;
        pc.* = Relocatable.default();
        var ap = allocator.create(Relocatable) catch unreachable;
        ap.* = Relocatable.default();
        var fp = allocator.create(Relocatable) catch unreachable;
        fp.* = Relocatable.default();
        return RunContext{
            .pc = pc,
            .ap = ap,
            .fp = fp,
        };
    }
};
