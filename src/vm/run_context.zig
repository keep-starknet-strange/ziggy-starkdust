// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Local imports.
const Relocatable = @import("memory/relocatable.zig").Relocatable;

// Contains the register states of the Cairo VM.
pub const RunContext = struct {
    allocator: *Allocator,
    pc: *Relocatable,
    ap: *Relocatable,
    fp: *Relocatable,

    pub fn init(allocator: *Allocator) !*RunContext {
        var run_context = try allocator.create(RunContext);
        run_context.* = RunContext{
            .allocator = allocator,
            .pc = try allocator.create(Relocatable),
            .ap = try allocator.create(Relocatable),
            .fp = try allocator.create(Relocatable),
        };
        run_context.pc.* = Relocatable.default();
        run_context.ap.* = Relocatable.default();
        run_context.fp.* = Relocatable.default();
        return run_context;
    }

    // Safe deallocation of the memory.
    pub fn deinit(self: *RunContext) void {
        self.allocator.destroy(self.pc);
        self.allocator.destroy(self.ap);
        self.allocator.destroy(self.fp);
    }
};
