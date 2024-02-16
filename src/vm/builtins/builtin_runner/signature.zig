const std = @import("std");
const Signature = @import("../../../math/crypto/signatures.zig").Signature;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const validation_rule = @import("../../memory/memory.zig").validation_rule;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const ecdsa_instance_def = @import("../../types/ecdsa_instance_def.zig");
const verify = @import("../../../math/crypto/signatures.zig").verify;

const CairoVM = @import("../../core.zig").CairoVM;

const MemoryError = @import("../../../vm/error.zig").MemoryError;
const MathError = @import("../../../vm/error.zig").MathError;
const RunnerError = @import("../../../vm/error.zig").RunnerError;

const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// inline closure for validation rule with self argument
pub inline fn SelfValidationRuleClosure(self: anytype, func: *const fn (@TypeOf(self), Allocator, *Memory, Relocatable) anyerror!std.ArrayList(Relocatable)) validation_rule {
    return (opaque {
        var hidden_self: @TypeOf(self) = undefined;
        var hidden_func: *const fn (@TypeOf(self), Allocator, *Memory, Relocatable) anyerror!std.ArrayList(Relocatable) = undefined;
        pub fn init(h_self: @TypeOf(self), h_func: *const fn (@TypeOf(self), Allocator, *Memory, Relocatable) anyerror!std.ArrayList(Relocatable)) *const @TypeOf(run) {
            hidden_self = h_self;
            hidden_func = h_func;
            return &run;
        }

        fn run(allocator: Allocator, memory: *Memory, r: Relocatable) anyerror!std.ArrayList(Relocatable) {
            return hidden_func(hidden_self, allocator, memory, r);
        }
    }).init(self, func);
}

/// Signature built-in runner
pub const SignatureBuiltinRunner = struct {
    const Self = @This();

    /// Included boolean flag
    included: bool,
    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize = 0,
    /// Number of cells per instance
    cells_per_instance: u32 = 2,
    /// Number of input cells
    n_input_cells: u32 = 2,
    /// Total number of bits
    total_n_bits: u32 = 251,
    /// Stop pointer
    stop_ptr: ?usize = null,
    /// Number of instances per component
    instances_per_component: u32 = 1,
    /// Signatures HashMap
    signatures: AutoHashMap(Relocatable, Signature),

    /// Create a new SignatureBuiltinRunner instance.
    ///
    /// This function initializes a new `SignatureBuiltinRunner` instance with the provided
    /// `allocator`, `instance_def`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the `signatures` HashMap.
    /// - `instance_def`: A pointer to the `EcdsaInstanceDef` for this runner.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `SignatureBuiltinRunner` instance.
    pub fn init(allocator: Allocator, instance_def: *ecdsa_instance_def.EcdsaInstanceDef, included: bool) Self {
        return .{
            .included = included,
            .ratio = instance_def.ratio,
            .signatures = AutoHashMap(Relocatable, Signature).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.signatures.deinit();
    }

    pub fn addSignature(self: *Self, relocatable: Relocatable, rs: struct { Felt252, Felt252 }) !void {
        try self.signatures.put(relocatable, .{
            .r = rs[0],
            .s = rs[1],
        });
    }

    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();

        if (self.included) {
            try result.append(MaybeRelocatable.fromRelocatable(Relocatable.init(@intCast(self.base), 0)));
        }

        return result;
    }

    fn validationRule(self: *Self, allocator: Allocator, memory: *Memory, addr: Relocatable) anyerror!std.ArrayList(Relocatable) {
        const cell_index = @mod(addr.offset, @as(u64, @intCast(self.cells_per_instance)));
        const result = std.ArrayList(Relocatable).init(allocator);

        const pubkey_message_addr = switch (cell_index) {
            0 => .{ addr, try addr.addUint(1) },
            1 => if (addr.subUint(1)) |prev_addr|
                .{ prev_addr, addr }
            else
                return result,
            else => return result,
        };

        const pubkey = memory.getFelt(pubkey_message_addr[0]) catch
            return if (cell_index == 1) result else MemoryError.PubKeyNonInt;
        const msg = memory.getFelt(pubkey_message_addr[1]) catch
            return if (cell_index == 0) result else MemoryError.MsgNonInt;

        const signature = self.signatures.get(pubkey_message_addr[0]) catch return MemoryError.SignatureNotFound;

        if (verify(pubkey, msg, signature.r, signature.s) catch
            return MemoryError.InvalidSignature)
        {
            return result;
        }

        return MemoryError.InvalidSignature;
    }

    /// Creates Validation Rule in Memory
    ///
    /// # Parameters
    ///
    /// - `memory`: A `Memory` pointer of validation rules segment index.
    ///
    /// # Modifies
    ///
    /// - `memory`: Adds validation rule to `memory`.
    pub fn addValidationRule(self: *Self, memory: *Memory) void {
        memory.addValidationRule(self.base, SelfValidationRuleClosure(self, &self.validationRule));
    }

    pub fn deduceMemoryCell(
        self: *const Self,
        address: Relocatable,
        memory: *Memory,
    ) ?MaybeRelocatable {
        _ = memory;
        _ = address;
        _ = self;
        return null;
    }

    pub fn getMemorySegmentAddresses(self: *const Self) struct { usize, ?usize } {
        return .{ self.base, self.stop_ptr };
    }

    pub fn getUsedCells(self: *const Self, segments: *MemorySegmentManager) MemoryError!usize {
        return segments.getSegmentUsedSize(@intCast(self.base)) orelse return MemoryError.MissingSegmentUsedSizes;
    }

    pub fn getUsedInstances(self: *const Self, segments: *MemorySegmentManager) !usize {
        return std.math.divCeil(
            usize,
            try self.getUsedCells(segments),
            @intCast(self.cells_per_instance),
        );
    }

    pub fn finalStack(
        self: *Self,
        segments: *MemorySegmentManager,
        pointer: Relocatable,
    ) !Relocatable {
        if (self.included) {
            const stop_pointer_addr = pointer.subUint(1) catch return RunnerError.NoStopPointer;

            const stop_pointer = segments.memory.getRelocatable(stop_pointer_addr) catch
                return RunnerError.NoStopPointer;

            if (self.base != stop_pointer.segment_index)
                return RunnerError.InvalidStopPointerIndex;

            const stop_ptr = stop_pointer.offset;
            const num_instances = try self.getUsedInstances(segments);

            const used = num_instances * @as(usize, @intCast(self.cells_per_instance));

            if (stop_ptr != used)
                return RunnerError.InvalidStopPointer;

            self.stop_ptr = stop_ptr;
            return stop_pointer_addr;
        } else {
            self.stop_ptr = 0;
            return pointer;
        }
    }
};

test "Signature: Used Cells" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(10);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memory_segment_manager.segment_used_sizes.put(0, 1);

    try std.testing.expectEqual(
        @as(usize, @intCast(1)),
        try builtin.getUsedCells(memory_segment_manager),
    );
}

test "Signature: initialize segments" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(10);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try builtin.initSegments(memory_segment_manager);

    try std.testing.expectEqual(0, builtin.base);
}

test "Signature: get used instances" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(10);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var memory_segment_manager = try MemorySegmentManager.init(std.testing.allocator);
    defer memory_segment_manager.deinit();

    try memory_segment_manager.segment_used_sizes.put(0, 1);

    try std.testing.expectEqual(
        1,
        try builtin.getUsedInstances(memory_segment_manager),
    );
}

test "Signature: final stack" {
    // default
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.segment_used_sizes.put(0, 0);

    const pointer = Relocatable.init(2, 2);

    try std.testing.expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(vm.segments, pointer),
    );
}

test "Signature: final stack error stop pointer" {
    // default
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.segment_used_sizes.put(0, 998);

    const pointer = Relocatable.init(2, 2);

    try std.testing.expectEqual(
        RunnerError.InvalidStopPointer,
        builtin.finalStack(vm.segments, pointer),
    );
}

test "Signature: final stack error non relocatable" {
    // default
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{2} },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.segment_used_sizes.put(0, 0);

    const pointer = Relocatable.init(2, 2);

    try std.testing.expectEqual(
        RunnerError.NoStopPointer,
        builtin.finalStack(vm.segments, pointer),
    );
}

// TODO: implement tests after implementing vm functions/builtin functions
// get_memory_accesses_missing_segment_used_sizes(
// get memory access empty
// get memory access

test "Signature: get used cells empty" {
    // default
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(0, 0);

    try std.testing.expectEqual(
        0,
        builtin.getUsedCells(vm.segments),
    );
}

test "Signature: get used cells" {
    // default
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(0, 4);

    try std.testing.expectEqual(
        4,
        builtin.getUsedCells(vm.segments),
    );
}

test "Signature: getInitialStackForRangeCheckWithBase" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    builtin.base = 1;

    const initial_stack = try builtin.initialStack(std.testing.allocator);
    defer initial_stack.deinit();

    try std.testing.expect(initial_stack.items[0].eq(
        MaybeRelocatable.fromRelocatable(Relocatable.init(@intCast(builtin.base), 0)),
    ));
}

test "Signature: initial stack not included test" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, false);

    const initial_stack = try builtin.initialStack(std.testing.allocator);
    defer initial_stack.deinit();

    try std.testing.expectEqual(0, initial_stack.items.len);
}

test "Signature: deduce memory cell" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    const result = builtin.deduceMemoryCell(Relocatable.init(0, 5), memory);

    try std.testing.expectEqual(null, result);
}

test "Signature: ratio" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    const builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    try std.testing.expectEqual(512, builtin.ratio);
}

test "Signature: base" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    const builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    try std.testing.expectEqual(0, builtin.base);
}

test "Signature: get memory segment addresses" {
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    const builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    try std.testing.expectEqual(.{ 0, null }, builtin.getMemorySegmentAddresses());
}
// TODO: implement when vm methods are implemented
// test "Signature: get used cells and allocated size insufficient allocated" {

test "Signature: final stack invalid stop pointer" {
    // default
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 1, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const pointer = Relocatable.init(0, 1);

    try std.testing.expectEqual(
        RunnerError.InvalidStopPointerIndex,
        builtin.finalStack(vm.segments, pointer),
    );
}

test "Signature: final stack no used insances" {
    // default
    var def = ecdsa_instance_def.EcdsaInstanceDef.init(512);

    var builtin = SignatureBuiltinRunner.init(std.testing.allocator, &def, true);

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
        },
    );
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const pointer = Relocatable.init(0, 1);

    try std.testing.expectEqual(
        MemoryError.MissingSegmentUsedSizes,
        builtin.finalStack(vm.segments, pointer),
    );
}
