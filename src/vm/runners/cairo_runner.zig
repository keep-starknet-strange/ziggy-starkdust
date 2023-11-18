// ************************************************************
// *                       IMPORTS                            *
// ************************************************************

// Core imports.
const std = @import("std");
const Allocator = std.mem.Allocator;
// Local imports.
const Config = @import("../config.zig").Config;
const vm_core = @import("../core.zig");
const relocatable = @import("../memory/relocatable.zig");
const Relocatable = relocatable.Relocatable;
const MaybeRelocatable = relocatable.MaybeRelocatable;
const newFromRelocatable = relocatable.newFromRelocatable;
const Program = @import("../types/program.zig").Program;

var finalPc: *Relocatable = undefined;
var mainOffset: usize = undefined;

pub const CairoRunner = struct {
    const Self = @This();

    // program: Program,
    allocator: Allocator,
    instructions: []MaybeRelocatable,
    vm: vm_core.CairoVM,
    programBase: Relocatable = undefined,
    executionBase: Relocatable = undefined,
    initialPc: Relocatable = undefined,
    initialAp: Relocatable = undefined,
    initialFp: Relocatable = undefined,
    // finalPc: *Relocatable,
    mainOffset: usize = 0,
    stack: std.ArrayList(MaybeRelocatable),
    // proofMode: bool,
    // runEnded: bool,
    // layout
    // execScopes
    // executionPublicMemory
    //Segments Finialized

    // the fundamental question is how to map this to zig, where you cant just have a bunch of uninitialized fields
    pub fn initFromConfig(allocator: Allocator, config: Config) !Self {
        // Create a new VM instance.
        var vm = try vm_core.CairoVM.init(
            allocator,
            config,
        );

        var instructions = try Program.dataFromFile(allocator, config.filename.?);

        var stack = std.ArrayList(MaybeRelocatable).init(allocator);

        return .{ .allocator = allocator, .instructions = instructions, .vm = vm, .mainOffset = 0, .stack = stack };
    }

    // no init
    pub fn init(self: *Self) !Relocatable {
        _ = self.initSegments();
        var end = try self.initMainEntryPoint();
        _ = self.initVM();
        return end;
    }

    pub fn initSegments(self: *Self) void {
        self.programBase = self.vm.segments.addSegment();
        self.executionBase = self.vm.segments.addSegment();
    }

    pub fn initState(self: *Self, entrypoint: usize) !void {
        self.initialPc = self.programBase;
        self.initialPc.addUintInPlace(entrypoint);

        _ = try self.vm.segments.memory.loadData(
            self.allocator,
            self.programBase,
            self.instructions,
        );

        _ = try self.vm.segments.memory.loadData(
            self.allocator,
            self.executionBase,
            self.stack.items,
        );
    }

    // initializeFunctionEntrypoint
    pub fn initFunctionEntrypoint(self: *Self, entrypoint: usize, return_fp: Relocatable) !Relocatable {
        var end = self.vm.segments.addSegment();
        // TODO sanity check order
        try self.stack.append(newFromRelocatable(return_fp));
        try self.stack.append(newFromRelocatable(end));
        std.log.debug(
            "stack items len: {?}",
            .{self.stack.items.len},
        );
        self.initialFp = self.executionBase;
        self.initialFp.addUintInPlace(@as(u64, self.stack.items.len));
        self.initialAp = self.initialFp;
        finalPc = &end;
        try self.initState(entrypoint);
        return end;
    }

    // initializeMainEntrypoint
    /// Initializes memory, initial register values and returns the endpointer
    /// to run from the main entrypoint
    pub fn initMainEntryPoint(self: *Self) !Relocatable {
        // when running from the main entrypoint,
        // only up to 11 values will be written
        // where 11 is derived from
        // 9 builtin bases + end + return_fp
        // sort of a misnomer because it returns MaybeRelocatable
        // try self.stack.append(relocatable.fromU256(0));
        // try self.stack.append(relocatable.fromU256(11));

        var return_fp = self.vm.segments.addSegment();
        return self.initFunctionEntrypoint(self.mainOffset, return_fp);
    }

    pub fn initVM(self: *Self) void {
        std.log.debug(
            "initialAp: {?} \n initialFp {?} \n initialPc {?}",
            .{ self.initialAp, self.initialFp, self.initialPc },
        );

        self.vm.run_context.ap.* = self.initialAp;
        self.vm.run_context.fp.* = self.initialFp;
        self.vm.run_context.pc.* = self.initialPc;
    }

    pub fn runUntilPC(self: *Self, end: Relocatable) void {
        while (!end.eq(self.vm.run_context.pc.*)) {
            std.log.debug("step {}\npc {}\n", .{ self.vm.current_step, self.vm.run_context.pc });
            self.vm.step(self.allocator) catch |err| {
                std.debug.print(
                    "Error: {}\n",
                    .{err},
                );
                return;
            };
        }
    }
};
