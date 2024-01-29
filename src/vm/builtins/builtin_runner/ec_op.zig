const std = @import("std");
const ec_op_instance_def = @import("../../types/ec_op_instance_def.zig");
const relocatable = @import("../../memory/relocatable.zig");
const CoreVM = @import("../../../vm/core.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const EC = @import("../../../math/fields/elliptic_curve.zig");
const Error = @import("../../error.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemoryError = Error.MemoryError;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const CairoVM = CoreVM.CairoVM;
const CairoVMError = @import("../../../vm/error.zig").CairoVMError;
const insertAtIndex = @import("../../../utils/testing.zig").insertAtIndex;
const RunnerError = Error.RunnerError;
const Tuple = std.meta.Tuple;

const EC_POINTS = [_]Tuple(&.{ usize, usize }){
    @as(std.meta.Tuple(&.{ usize, usize }), .{ 0, 1 }),
    @as(std.meta.Tuple(&.{ usize, usize }), .{ 2, 3 }),
    @as(std.meta.Tuple(&.{ usize, usize }), .{ 5, 6 }),
};
const OUTPUT_INDICES = EC_POINTS[2];

/// EC Operation built-in runner
pub const EcOpBuiltinRunner = struct {
    const Self = @This();

    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize,
    /// Number of cells per instance
    cells_per_instance: u32,
    /// Number of input cells
    n_input_cells: u32,
    /// Built-in EC Operation instance
    ec_op_builtin: ec_op_instance_def.EcOpInstanceDef,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,
    /// Number of instance per component
    instances_per_component: u32,
    /// Cache
    cache: AutoHashMap(Relocatable, Felt252),

    /// Create a new ECOpBuiltinRunner instance.
    ///
    /// This function initializes a new `EcOpBuiltinRunner` instance with the provided
    /// `allocator`, `instance_def`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the cache.
    /// - `instance_def`: A pointer to the `EcOpInstanceDef` for this runner.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `EcOpBuiltinRunner` instance.
    pub fn init(
        allocator: Allocator,
        instance_def: ec_op_instance_def.EcOpInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .base = 0,
            .n_input_cells = ec_op_instance_def.INPUT_CELLS_PER_EC_OP,
            .cells_per_instance = ec_op_instance_def.CELLS_PER_EC_OP,
            .ec_op_builtin = instance_def,
            .stop_ptr = null,
            .included = included,
            .instances_per_component = 1,
            .cache = AutoHashMap(Relocatable, Felt252).init(allocator),
        };
    }

    pub fn initDefault(allocator: Allocator) Self {
        return Self.init(allocator, &@as(ec_op_instance_def.EcOpInstanceDef, .{}), true);
    }

    /// Initializes memory segments and sets the base value for the EC OP runner.
    ///
    /// This function adds a memory segment using the provided `segments` manager and
    /// sets the `base` value to the index of the new segment.
    ///
    /// # Parameters
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment management.
    ///
    /// # Modifies
    /// - `self`: Updates the `base` value to the new segment's index.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    /// Initializes and returns an `ArrayList` of `MaybeRelocatable` values.
    ///
    /// If the EC OP runner is included, it appends a `Relocatable` element to the `ArrayList`
    /// with the base value. Otherwise, it returns an empty `ArrayList`.
    ///
    /// # Parameters
    /// - `allocator`: An allocator for initializing the `ArrayList`.
    ///
    /// # Returns
    /// An `ArrayList` of `MaybeRelocatable` values.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        if (self.included) {
            try result.append(.{
                .relocatable = Relocatable.new(
                    @intCast(self.base),
                    0,
                ),
            });
            return result;
        }
        return result;
    }

    /// Deduces the `MemoryCell`, where deduction in the case of EC OP
    /// is the result of the elliptic curve operation P + m * Q,
    /// where P = const_partial_sum, and Q = const_doubled_point
    /// are points on the elliptic curve defined as:
    /// y^2 = x^3 + alpha * x + beta.
    ///
    /// # Parameters
    ///
    /// - `address`: The target address for deducing the `MemoryCell`.
    /// - `memory`: A pointer to the `Memory` containing the memory segments.
    ///
    /// # Returns
    ///
    /// A `MaybeRelocatable` containing the deduced `MemoryCell`, or `null` if the address
    /// corresponds to an input cell, or an error code if any issues occur during the process.
    pub fn deduceMemoryCell(self: *Self, allocator: Allocator, address: Relocatable, memory: *Memory) !?MaybeRelocatable {
        const index = address.offset % self.cells_per_instance;
        if ((index != OUTPUT_INDICES[0]) and (index != OUTPUT_INDICES[1])) return error.NotOutputCell;

        const instance = Relocatable.init(address.segment_index, address.offset - index);
        const x_addr = try instance.addFelt(Felt252.fromInt(u256, self.n_input_cells));

        if (self.cache.get(address)) |value| {
            return MaybeRelocatable.fromFelt(value);
        }

        var input_cells = ArrayList(Felt252).init(allocator);
        defer input_cells.deinit();

        // All input cells should be filled, and be integer values.
        for (0..self.n_input_cells) |i| {
            if (memory.get(try instance.addFelt(Felt252.fromInt(u256, i)))) |cell| {
                const felt = try cell.tryIntoFelt();
                try input_cells.append(felt);
            }
        }

        for (EC_POINTS[0..2]) |pair| {
            const x = input_cells.items[pair[0]];
            const y = input_cells.items[pair[1]];
            var point = EC.ECPoint{ .x = x, .y = y };
            if (!point.pointOnCurve(EC.ALPHA, EC.BETA)) return error.PointNotOnCurve;
        }

        const height = 256;

        const partial_sum = EC.ECPoint{
            .x = input_cells.items[0],
            .y = input_cells.items[1],
        };

        const doubled_point = EC.ECPoint{
            .x = input_cells.items[2],
            .y = input_cells.items[3],
        };

        const result = try EC.ecOpImpl(partial_sum, doubled_point, input_cells.items[4], EC.ALPHA, height);
        try self.cache.put(x_addr, result.x);
        try self.cache.put(try x_addr.addFelt(Felt252.one()), result.x);

        return switch (index - self.n_input_cells) {
            0 => MaybeRelocatable.fromFelt(result.x),
            else => MaybeRelocatable.fromFelt(result.y),
        };
    }

    /// Get the number of used cells associated with this EC OP runner.
    ///
    /// # Parameters
    ///
    /// - `segments`: A pointer to a `MemorySegmentManager` for segment size information.
    ///
    /// # Returns
    ///
    /// The number of used cells as a `u32`, or `MemoryError.MissingSegmentUsedSizes` if
    /// the size is not available.
    pub fn getUsedCells(self: *Self, segments: *MemorySegmentManager) !u32 {
        return segments.getSegmentUsedSize(@intCast(self.base)) orelse MemoryError.MissingSegmentUsedSizes;
    }

    /// Calculates the number of used instances for the EC OP runner.
    ///
    /// This function computes the number of used instances based on the available
    /// used cells and the number of cells per instance. It performs a ceiling division
    /// to ensure that any remaining cells are counted as an additional instance.
    ///
    /// # Parameters
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment information.
    ///
    /// # Returns
    /// The number of used instances as a `usize`.
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !usize {
        return std.math.divCeil(
            usize,
            try self.getUsedCells(segments),
            self.cells_per_instance,
        );
    }

    /// Retrieves memory access `Relocatable` for the EC OP runner.
    ///
    /// This function returns an `ArrayList` of `Relocatable` elements, each representing
    /// a memory access within the segment associated with the EC OP runner's base.
    ///
    /// # Parameters
    /// - `allocator`: An allocator for initializing the `ArrayList`.
    /// - `vm`: A pointer to the `CairoVM` containing segment information.
    ///
    /// # Returns
    /// An `ArrayList` of `Relocatable` elements.
    pub fn getMemoryAccesses(
        self: *Self,
        allocator: Allocator,
        vm: *CairoVM,
    ) !ArrayList(Relocatable) {
        const segment_size = try (vm.segments.getSegmentUsedSize(
            @intCast(self.base),
        ) orelse MemoryError.MissingSegmentUsedSizes);
        var result = ArrayList(Relocatable).init(allocator);
        for (0..segment_size) |i| {
            try result.append(.{
                .segment_index = @intCast(self.base),
                .offset = i,
            });
        }
        return result;
    }

    /// Retrieves memory segment addresses as a tuple.
    ///
    /// Returns a tuple containing the `base` and `stop_ptr` addresses associated
    /// with the EC OP runner's memory segments. The `stop_ptr` may be `null`.
    ///
    /// # Returns
    /// A tuple of `usize` and `?usize` addresses.
    pub fn getMemorySegmentAddresses(self: *Self) std.meta.Tuple(&.{ usize, ?usize }) {
        return .{
            self.base,
            self.stop_ptr,
        };
    }

    /// Calculate the final stack.
    ///
    /// This function calculates the final stack pointer for the EC OP runner, based on the provided `segments`, `pointer`, and `self` settings. If the runner is included,
    /// it verifies the stop pointer for consistency and sets it. Otherwise, it sets the stop pointer to zero.
    ///
    /// # Parameters
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` for segment management.
    /// - `pointer`: A `Relocatable` pointer to the current stack pointer.
    ///
    /// # Returns
    ///
    /// A `Relocatable` pointer to the final stack pointer, or an error code if the
    /// verification fails.
    pub fn finalStack(
        self: *Self,
        segments: *MemorySegmentManager,
        pointer: Relocatable,
    ) !Relocatable {
        if (self.included) {
            const stop_pointer_addr = pointer.subUint(1) catch return RunnerError.NoStopPointer;
            const stop_pointer = try (segments.memory.get(stop_pointer_addr) orelse return RunnerError.NoStopPointer).tryIntoRelocatable();
            if (self.base != stop_pointer.segment_index) {
                return RunnerError.InvalidStopPointerIndex;
            }
            const stop_ptr = stop_pointer.offset;

            if (stop_ptr != try self.getUsedInstances(segments) * @as(
                usize,
                @intCast(self.cells_per_instance),
            )) {
                return RunnerError.InvalidStopPointer;
            }
            self.stop_ptr = stop_ptr;
            return stop_pointer_addr;
        }

        self.stop_ptr = 0;
        return pointer;
    }

    /// Frees the resources owned by this instance of `EcOpBuiltinRunner`.
    pub fn deinit(self: *Self) void {
        self.cache.deinit();
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

test "ECOPBuiltinRunner: assert that the number of instances used by the builtin is correct" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    const segment = try vm.segments.addSegment();
    try vm.segments.segment_used_sizes.put(@intCast(segment.segment_index), 1);

    try expectEqual(try builtin.getUsedInstances(vm.segments), 1);
}

test "ECOPBuiltinRunner: final stack success" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );

    var segment_used_size = std.ArrayHashMap(
        i64,
        u32,
        std.array_hash_map.AutoContext(i64),
        false,
    ).init(std.testing.allocator);

    try segment_used_size.put(0, 0);
    vm.segments.segment_used_sizes = segment_used_size;

    const pointer = Relocatable.init(2, 2);

    try expectEqual(
        Relocatable.init(2, 1),
        try builtin.finalStack(vm.segments, pointer),
    );
}

test "ECOPBuiltinRunner: final stack error stop pointer" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );

    var segment_used_size = std.ArrayHashMap(
        i64,
        u32,
        std.array_hash_map.AutoContext(i64),
        false,
    ).init(std.testing.allocator);

    try segment_used_size.put(0, 999);
    vm.segments.segment_used_sizes = segment_used_size;

    const pointer = Relocatable.new(2, 2);

    try expectError(
        RunnerError.InvalidStopPointer,
        builtin.finalStack(vm.segments, pointer),
    );
}

test "ECOPBuiltinRunner: final stack error when not included" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, false);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{ 0, 0 } },
        },
    );

    var segment_used_size = std.ArrayHashMap(
        i64,
        u32,
        std.array_hash_map.AutoContext(i64),
        false,
    ).init(std.testing.allocator);

    try segment_used_size.put(0, 0);
    vm.segments.segment_used_sizes = segment_used_size;

    const pointer = Relocatable.new(2, 2);

    try expectEqual(
        pointer,
        try builtin.finalStack(vm.segments, pointer),
    );
}

test "ECOPBuiltinRunner: final stack error non relocatable" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{ 0, 0 } },
            .{ .{ 0, 1 }, .{ 0, 1 } },
            .{ .{ 2, 0 }, .{ 0, 0 } },
            .{ .{ 2, 1 }, .{2} },
        },
    );

    var segment_used_size = std.ArrayHashMap(
        i64,
        u32,
        std.array_hash_map.AutoContext(i64),
        false,
    ).init(std.testing.allocator);

    try segment_used_size.put(0, 0);
    vm.segments.segment_used_sizes = segment_used_size;

    const pointer = Relocatable.new(2, 2);

    try expectError(
        CairoVMError.TypeMismatchNotRelocatable,
        builtin.finalStack(vm.segments, pointer),
    );
}

test "ECOPBuiltinRunner: get allocated memory units" {}

test "ECOPBuiltinRunner: deduce memory cell ec op for preset memory valid" {
    //    Data taken from this program execution:

    //    %builtins output ec_op
    //    from starkware.cairo.common.cairo_builtins import EcOpBuiltin
    //    from starkware.cairo.common.serialize import serialize_word
    //    from starkware.cairo.common.ec_point import EcPoint
    //    from starkware.cairo.common.ec import ec_op

    //    func main{output_ptr: felt*, ec_op_ptr: EcOpBuiltin*}():
    //        let x: EcPoint = EcPoint(2089986280348253421170679821480865132823066470938446095505822317253594081284, 1713931329540660377023406109199410414810705867260802078187082345529207694986)

    //        let y: EcPoint = EcPoint(874739451078007766457464989774322083649278607533249481151382481072868806602,152666792071518830868575557812948353041420400780739481342941381225525861407)
    //        let z: EcPoint = ec_op(x,34, y)
    //        serialize_word(z.x)
    //        return()
    //        end

    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{
                .{ 3, 0 },
                .{@as(u256, 0x68caa9509b7c2e90b4d92661cbf7c465471c1e8598c5f989691eef6653e0f38)},
            },
            .{
                .{ 3, 1 },
                .{@as(u256, 0x79a8673f498531002fc549e06ff2010ffc0c191cceb7da5532acb95cdcb591)},
            },
            .{
                .{ 3, 2 },
                .{@as(u256, 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca)},
            },
            .{
                .{ 3, 3 },
                .{@as(u256, 0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f)},
            },
            .{ .{ 3, 4 }, .{34} },
            .{ .{ 3, 5 }, .{2778063437308421278851140253538604815869848682781135193774472480292420096757} },
        },
    );

    const expected = Felt252.fromInt(u256, 3598390311618116577316045819420613574162151407434885460365915347732568210029);
    const actual = try builtin.deduceMemoryCell(std.testing.allocator, Relocatable.new(3, 6), vm.segments.memory);

    try expectEqual(
        MaybeRelocatable.fromFelt(expected),
        actual,
    );
}

test "ECOPBuiltinRunner: deduce memory cell ec op for preset memory unfilled input cells" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{
                .{ 3, 1 },
                .{@as(u256, 0x79a8673f498531002fc549e06ff2010ffc0c191cceb7da5532acb95cdcb591)},
            },
            .{
                .{ 3, 2 },
                .{@as(u256, 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca)},
            },
            .{
                .{ 3, 3 },
                .{@as(u256, 0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f)},
            },
            .{ .{ 3, 4 }, .{34} },
            .{ .{ 3, 5 }, .{2778063437308421278851140253538604815869848682781135193774472480292420096757} },
        },
    );

    const actual = builtin.deduceMemoryCell(std.testing.allocator, Relocatable.new(3, 6), vm.segments.memory);

    try expectError(
        error.PointNotOnCurve,
        actual,
    );
}

test "ECOPBuiltinRunner: deduce memory cell ec op for preset memory addr not an output cell" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{
                .{ 3, 1 },
                .{@as(u256, 0x79a8673f498531002fc549e06ff2010ffc0c191cceb7da5532acb95cdcb591)},
            },
            .{
                .{ 3, 2 },
                .{@as(u256, 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca)},
            },
            .{
                .{ 3, 3 },
                .{@as(u256, 0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f)},
            },
            .{ .{ 3, 4 }, .{34} },
            .{ .{ 3, 5 }, .{2778063437308421278851140253538604815869848682781135193774472480292420096757} },
        },
    );

    const actual = builtin.deduceMemoryCell(std.testing.allocator, Relocatable.new(3, 3), vm.segments.memory);

    try expectError(
        error.NotOutputCell,
        actual,
    );
}

test "ECOPBuiltinRunner: deduce memory cell ec op for preset memory non integer input" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{
                .{ 3, 1 },
                .{@as(u256, 0x79a8673f498531002fc549e06ff2010ffc0c191cceb7da5532acb95cdcb591)},
            },
            .{
                .{ 3, 2 },
                .{@as(u256, 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca)},
            },
            .{
                .{ 3, 3 },
                .{ 1, 2 },
            },
            .{ .{ 3, 4 }, .{34} },
            .{ .{ 3, 5 }, .{2778063437308421278851140253538604815869848682781135193774472480292420096757} },
        },
    );

    const actual = builtin.deduceMemoryCell(std.testing.allocator, Relocatable.new(3, 6), vm.segments.memory);

    try expectError(
        error.TypeMismatchNotFelt,
        actual,
    );
}

test "ECOPBuiltinRunner: get memory segment addresses" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    const expected: std.meta.Tuple(&.{ usize, ?usize }) = .{ 0, @as(?usize, null) };
    const actual: std.meta.Tuple(&.{ usize, ?usize }) = builtin.getMemorySegmentAddresses();
    try expectEqual(expected, actual);
}

test "ECOPBuiltinRunner: get memory accesses missing segment used sizes" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(0, 0);

    const actual = try builtin.getMemoryAccesses(std.testing.allocator, &vm);
    defer actual.deinit();
    try expectEqualSlices(Relocatable, &[_]Relocatable{}, actual.items);
}

test "ECOPBuiltinRunner: get memory accesses empty" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(0, 0);

    const actual = try builtin.getMemoryAccesses(std.testing.allocator, &vm);
    defer actual.deinit();
    try expectEqualSlices(Relocatable, &[_]Relocatable{}, actual.items);
}

test "ECOPBuiltinRunner: get memory accesses" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(0, 4);

    const expected = [_]Relocatable{
        Relocatable.init(@intCast(builtin.base), 0),
        Relocatable.init(@intCast(builtin.base), 1),
        Relocatable.init(@intCast(builtin.base), 2),
        Relocatable.init(@intCast(builtin.base), 3),
    };

    var actual = try builtin.getMemoryAccesses(std.testing.allocator, &vm);
    defer actual.deinit();
    try expectEqualSlices(Relocatable, &expected, actual.items);
}

test "ECOPBuiltinRunner: get used cells missing segment used sizes" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try expectError(MemoryError.MissingSegmentUsedSizes, builtin.getUsedCells(vm.segments));
}

test "ECOPBuiltinRunner: get used cells empty" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    try vm.segments.segment_used_sizes.put(0, 0);

    try expectEqual(0, try builtin.getUsedCells(vm.segments));
}

test "ECOPBuiltinRunner: get used cells and allocated size test" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    const segment = try vm.segments.addSegment();
    try vm.segments.segment_used_sizes.put(@intCast(segment.segment_index), 4);

    try expectEqual(4, builtin.getUsedCells(vm.segments));
}

test "ECOPBuiltinRunner: get used cells success" {
    const instance_def = ec_op_instance_def.EcOpInstanceDef{
        .ratio = 10,
    };
    var builtin = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true);
    defer builtin.deinit();

    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    const segment = try vm.segments.addSegment();
    try vm.segments.segment_used_sizes.put(@intCast(segment.segment_index), 4);

    try expectEqual(4, builtin.getUsedCells(vm.segments));
}
