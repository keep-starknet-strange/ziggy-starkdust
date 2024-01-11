const std = @import("std");
const ec_op_instance_def = @import("../../types/ec_op_instance_def.zig");
const relocatable = @import("../../memory/relocatable.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const EC = @import("../../../math/fields/elliptic_curve.zig");
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;

const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
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
        instance_def: *ec_op_instance_def.EcOpInstanceDef,
        included: bool,
    ) Self {
        return .{
            .ratio = instance_def.ratio,
            .base = 0,
            .n_input_cells = ec_op_instance_def.INPUT_CELLS_PER_EC_OP,
            .cell_per_instance = ec_op_instance_def.CELLS_PER_EC_OP,
            .ec_op_builtin = instance_def,
            .stop_ptr = null,
            .included = included,
            .instances_per_component = 1,
            .cache = AutoHashMap(Relocatable, Felt252).init(allocator),
        };
    }

    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        _ = self;
        _ = segments;
    }

    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        _ = self;
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();
        return result;
    }

    pub fn deduceMemoryCell(self: *const Self, allocator: Allocator, address: Relocatable, memory: *Memory) !?MaybeRelocatable {
        const index = address.offset % self.cells_per_instance;
        if ((index != OUTPUT_INDICES[0]) and (index != OUTPUT_INDICES[1])) return null;

        const instance = Relocatable.init(address.segment_index, address.offset - index);
        const x_addr = try instance.addFelt(Felt252.fromInteger(self.n_input_cells));

        if (self.cache.get(address)) |value| {
            return MaybeRelocatable.fromFelt(value);
        }

        var input_cells = ArrayList(Felt252).init(allocator);

        // All input cells should be filled, and be integer values.
        for (0..self.n_input_cells) |i| {
            if (memory.get(try instance.addFelt(Felt252.fromInteger(i)))) |cell| {
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
        try self.cache.put(x_addr, result[0]);
        try self.cache.put(x_addr.addFelt(Felt252.one()), result[0]);

        return null;
    }
};
