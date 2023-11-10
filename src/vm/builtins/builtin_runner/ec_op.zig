const std = @import("std");
const ec_op_instance_def = @import("../../types/ec_op_instance_def.zig");
const Memory = @import("../../memory/memory.zig").Memory;
const relocatable = @import("../../memory/relocatable.zig");
const MaybeRelocatable = relocatable.MaybeRelocatable;
const Relocatable = relocatable.Relocatable;
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;

const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

const ALPHA = Felt252.one();
const BETA = Felt252.fromInteger(3141592653589793238462643383279502884197169399375105820974944592307816406665);

// Error type to represent different error conditions during bitwise builtin.
pub const EcOpError = error{};

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
    cache: AutoHashMap(relocatable.Relocatable, Felt252),

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
    pub fn new(
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
            .cache = AutoHashMap(relocatable.Relocatable, Felt252).init(allocator),
        };
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
};

/// Compute the auto-deduction rule for EcOp builtin.
/// # Arguments
/// - `address`: The address belonging to the EcOp builtin's segment
/// - `memory`: The cairo memory where addresses are looked up
/// # Returns
/// The deduced value as a `MaybeRelocatable`
pub fn deduce(address: Relocatable, memory: *Memory) EcOpError!MaybeRelocatable {
    _ = memory;
    _ = address;
}

// Returns the result of the EC operation P + m * Q
// where P = (p_x, p_y), Q = (q_x, q_y) are points on the elliptic curve defined as
// y^2 = x^3 + alpha * x + beta.
pub fn ecOpImpl(
    p_x: Felt252,
    p_y: Felt252,
    q_x: Felt252,
    q_y: Felt252,
    m: Felt252,
    alpha: Felt252,
    height: u32,
) void {
    var slope: u256 = m.toInteger();
    var partial_sum: std.meta.Tuple(&[_]type{ u256, u256 }) = .{ p_x.toInteger(), p_y.toInteger() };
    var doubled_point: std.meta.Tuple(&[_]type{ u256, u256 }) = .{ q_x.toInteger(), q_y.toInteger() };

    var i: u32 = 0;
    while (i < height) : (i += 1) {
        // TODO: implement the loop.
    }

    _ = doubled_point;
    _ = alpha;
    _ = slope;
    _ = partial_sum;
}

/// Check if the point is on the elliptic curve with the equation y^2 = x^3 + alpha*x + beta.
/// # Arguments
/// - `x`: The x coordinate of the point.
/// - `y`: The y coordinate of the point.
/// # Returns
/// A boolean indicating whether the point is on the curve.
pub fn pointOnCurve(
    x: Felt252,
    y: Felt252,
    alpha: Felt252,
    beta: Felt252,
) bool {
    const left_side = y.pow(2);
    const right_side = (x.pow(3).add(alpha.mul(x))).add(beta);
    const is_on_curve = (left_side.equal(right_side));
    return is_on_curve;
}

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;

test "point A is on curve" {
    const x = Felt252.fromInteger(874739451078007766457464989774322083649278607533249481151382481072868806602);
    const y = Felt252.fromInteger(152666792071518830868575557812948353041420400780739481342941381225525861407);
    const alpha = ALPHA;
    const beta = BETA;
    try expect(pointOnCurve(x, y, alpha, beta));
}

test "point B is on curve" {
    const x = Felt252.fromInteger(3139037544796708144595053687182055617920475701120786241351436619796497072089);
    const y = Felt252.fromInteger(2119589567875935397690285099786081818522144748339117565577200220779667999801);
    const alpha = ALPHA;
    const beta = BETA;
    try expect(pointOnCurve(x, y, alpha, beta));
}

test "point C is not on curve" {
    const x = Felt252.fromInteger(874739454078007766457464989774322083649278607533249481151382481072868806602);
    const y = Felt252.fromInteger(152666792071518830868575557812948353041420400780739481342941381225525861407);
    const alpha = ALPHA;
    const beta = BETA;
    try expect(!pointOnCurve(x, y, alpha, beta));
}

test "point D is not on curve" {
    const x = Felt252.fromInteger(3139037544756708144595053687182055617927475701120786241351436619796497072089);
    const y = Felt252.fromInteger(2119589567875935397690885099786081818522144748339117565577200220779667999801);
    const alpha = ALPHA;
    const beta = BETA;
    try expect(!pointOnCurve(x, y, alpha, beta));
}
