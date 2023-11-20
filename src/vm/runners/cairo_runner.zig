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

pub const CairoRunner = struct {
    const Self = @This();

    // program: Program,
    allocator: Allocator,
    instructions: []MaybeRelocatable,
    vm: vm_core.CairoVM,
    program_base: Relocatable = undefined,
    execution_base: Relocatable = undefined,
    initial_pc: Relocatable = undefined,
    initial_ap: Relocatable = undefined,
    initial_fp: Relocatable = undefined,
    final_pc: *Relocatable = undefined,
    main_offset: usize = 0,
    stack: std.ArrayList(MaybeRelocatable),
    // proofMode: bool,
    // runEnded: bool,
    // layout
    // execScopes
    // executionPublicMemory
    // Segments Finialized

    pub fn initFromConfig(allocator: Allocator, config: Config) !Self {
        // Create a new VM instance.
        var vm = try vm_core.CairoVM.init(
            allocator,
            config,
        );

        var instructions = try Program.dataFromFile(allocator, config.filename.?);

        var stack = std.ArrayList(MaybeRelocatable).init(allocator);

        return .{ .allocator = allocator, .instructions = instructions, .vm = vm, .stack = stack };
    }

    pub fn setupExecutionState(self: *Self) !Relocatable {
        _ = self.initSegments();
        var end = try self.initMainEntryPoint();
        _ = self.initVM();
        return end;
    }

    pub fn initSegments(self: *Self) void {
        self.program_base = self.vm.segments.addSegment();
        self.execution_base = self.vm.segments.addSegment();
    }

    pub fn initState(self: *Self, entrypoint: usize) !void {
        self.initial_pc = self.program_base;
        self.initial_pc.addUintInPlace(entrypoint);

        _ = try self.vm.segments.memory.loadData(
            self.allocator,
            self.program_base,
            self.instructions,
        );

        _ = try self.vm.segments.memory.loadData(
            self.allocator,
            self.execution_base,
            self.stack.items,
        );
    }

    // initializeFunctionEntrypoint
    pub fn initFunctionEntrypoint(self: *Self, entrypoint: usize, return_fp: Relocatable) !Relocatable {
        var end = self.vm.segments.addSegment();

        try self.stack.append(newFromRelocatable(return_fp));
        try self.stack.append(newFromRelocatable(end));

        self.initial_fp = self.execution_base;
        self.initial_fp.addUintInPlace(@as(u64, self.stack.items.len));
        self.initial_ap = self.initial_fp;

        self.final_pc = &end;
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

        var return_fp = self.vm.segments.addSegment();
        return self.initFunctionEntrypoint(self.main_offset, return_fp);
    }

    pub fn initVM(self: *Self) void {
        self.vm.run_context.ap.* = self.initial_ap;
        self.vm.run_context.fp.* = self.initial_fp;
        self.vm.run_context.pc.* = self.initial_pc;
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

    pub fn deinit(self: *Self) void {
        // Deinitialize and deallocate instructions array.
        self.allocator.free(self.instructions);

        // Deinitialize the stack. This will deallocate the memory used by the stack itself,
        // but not the memory of the elements within it, if they are pointers.
        self.stack.deinit();

        // Deinitialize the VM, which should take care of its own resources.
        self.vm.deinit();
    }
};
