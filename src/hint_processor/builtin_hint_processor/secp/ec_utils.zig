const std = @import("std");

const testing_utils = @import("../../testing_utils.zig");
const CoreVM = @import("../../../vm/core.zig");
const field_helper = @import("../../../math/fields/helper.zig");
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const fromBigInt = @import("../../../math/fields/starknet.zig").fromBigInt;
const MaybeRelocatable = @import("../../../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../../../vm/memory/relocatable.zig").Relocatable;
const CairoVM = CoreVM.CairoVM;
const hint_utils = @import("../../hint_utils.zig");
const HintReference = @import("../../hint_processor_def.zig").HintReference;
const hint_codes = @import("../../builtin_hint_codes.zig");
const Allocator = std.mem.Allocator;
const ApTracking = @import("../../../vm/types/programjson.zig").ApTracking;
const ExecutionScopes = @import("../../../vm/types/execution_scopes.zig").ExecutionScopes;

const MathError = @import("../../../vm/error.zig").MathError;
const HintError = @import("../../../vm/error.zig").HintError;
const CairoVMError = @import("../../../vm/error.zig").CairoVMError;

const bigint_utils = @import("bigint_utils.zig");
const secp_utils = @import("secp_utils.zig");

const BigInt3 = bigint_utils.BigInt3;
const Int = @import("std").math.big.int.Managed;

const EcPoint = struct {
    x: BigInt3,
    y: BigInt3,

    fn fromVarName(
        name: []const u8,
        vm: *CairoVM,
        ids_data: std.StringHashMap(HintReference),
        ap_tracking: ApTracking,
    ) !EcPoint {
        // Get first addr of EcPoint struct
        const point_addr = try hint_utils.getRelocatableFromVarName(name, vm, ids_data, ap_tracking);

        return .{
            .x = try BigInt3.fromBaseAddr(point_addr, vm),
            .y = try BigInt3.fromBaseAddr(try point_addr.addUint(3), vm),
        };
    }
};

// Implements main logic for `EC_NEGATE` and `EC_NEGATE_EMBEDDED_SECP` hints
pub fn ecNegate(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    secp_p: Int,
) !void {
    //ids.point
    const point_y = try (try hint_utils.getRelocatableFromVarName("point", vm, ids_data, ap_tracking)).addUint(3);
    const y_bigint3 = try BigInt3.fromBaseAddr(point_y, vm);

    var y = try y_bigint3.pack86(allocator);
    defer y.deinit();

    y.negate();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var value = try Int.init(allocator);
    errdefer value.deinit();

    try tmp.divFloor(&value, &y, &secp_p);

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = try secp_p.clone() });
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

//     y = pack(ids.point.y, PRIME) % SECP_P
//     # The modulo operation in python always returns a nonnegative number.
//     value = (-y) % SECP_P
// %}
pub fn ecNegateImportSecpP(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var val = try Int.initSet(allocator, secp_utils.SECP_P);
    defer val.deinit();

    try ecNegate(allocator, vm, exec_scopes, ids_data, ap_tracking, val);
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import pack
//     SECP_P = 2**255-19

//     y = pack(ids.point.y, PRIME) % SECP_P
//     # The modulo operation in python always returns a nonnegative number.
//     value = (-y) % SECP_P
// %}
pub fn ecNegateEmbeddedSecpP(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    var secp_p = try Int.initSet(allocator, (1 << 255) - 19);
    defer secp_p.deinit();

    try ecNegate(allocator, vm, exec_scopes, ids_data, ap_tracking, secp_p);
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack
//     from starkware.python.math_utils import ec_double_slope

//     # Compute the slope.
//     x = pack(ids.point.x, PRIME)
//     y = pack(ids.point.y, PRIME)
//     value = slope = ec_double_slope(point=(x, y), alpha=0, p=SECP_P)
// %}
pub fn computeDoublingSlope(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    point_alias: []const u8,
    secp_p_v: anytype,
    alpha_v: anytype,
) !void {
    var alpha = try Int.initSet(allocator, alpha_v);
    defer alpha.deinit();

    var secp_p = try Int.initSet(allocator, secp_p_v);
    errdefer secp_p.deinit();

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    //ids.point
    const point = try EcPoint.fromVarName(point_alias, vm, ids_data, ap_tracking);

    var p1 = try point.x.pack86(allocator);
    defer p1.deinit();
    var p2 = try point.y.pack86(allocator);
    defer p2.deinit();

    var value = try ecDoubleSlope(allocator, .{ p1, p2 }, alpha, secp_p);
    errdefer value.deinit();

    var slope = try value.clone();
    errdefer slope.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
}

/// Computes the slope of an elliptic curve with the equation y^2 = x^3 + alpha*x + beta mod p, at
/// the given point.
/// Assumes the point is given in affine form (x, y) and has y != 0.
pub fn ecDoubleSlope(
    allocator: std.mem.Allocator,
    point: struct { Int, Int },
    alpha: Int,
    prime: Int,
) !Int {
    var tmp = try Int.initSet(allocator, 3);
    defer tmp.deinit();
    var tmp2 = try Int.initSet(allocator, 2);
    defer tmp2.deinit();

    try tmp.mul(&tmp, &point[0]);
    try tmp.mul(&tmp, &point[0]);
    try tmp.add(&tmp, &alpha);

    try tmp2.mul(&tmp2, &point[1]);

    return field_helper.divModBigInt(allocator, &tmp, &tmp2, &prime);
}

/// Computes the slope of the line connecting the two given EC points over the field GF(p).
/// Assumes the points are given in affine form (x, y) and have different x coordinates.
pub fn lineSlope(
    allocator: std.mem.Allocator,
    point_a: struct { Int, Int },
    point_b: struct { Int, Int },
    prime: Int,
) !Int {
    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var tmp1 = try Int.init(allocator);
    defer tmp1.deinit();

    try tmp.sub(&point_a[1], &point_b[1]);
    try tmp1.sub(&point_a[0], &point_b[0]);

    return field_helper.divModBigInt(allocator, &tmp, &tmp1, &prime);
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import pack
//     from starkware.python.math_utils import ec_double_slope

//     # Compute the slope.
//     x = pack(ids.point.x, PRIME)
//     y = pack(ids.point.y, PRIME)
//     value = slope = ec_double_slope(point=(x, y), alpha=ALPHA, p=SECP_P)
// %}
pub fn computeDoublingSlopeExternalConsts(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //ids.point
    const point = try EcPoint.fromVarName("point", vm, ids_data, ap_tracking);
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");
    const alpha = try exec_scopes.getValue(Int, "ALPHA");

    var p1 = try point.x.pack86(allocator);
    defer p1.deinit();

    var p2 = try point.y.pack86(allocator);
    defer p2.deinit();

    var value = try ecDoubleSlope(allocator, .{ p1, p2 }, alpha, secp_p);
    errdefer value.deinit();

    var slope = try value.clone();
    errdefer slope.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack
//     from starkware.python.math_utils import line_slope

//     # Compute the slope.
//     x0 = pack(ids.point0.x, PRIME)
//     y0 = pack(ids.point0.y, PRIME)
//     x1 = pack(ids.point1.x, PRIME)
//     y1 = pack(ids.point1.y, PRIME)
//     value = slope = line_slope(point1=(x0, y0), point2=(x1, y1), p=SECP_P)
// %}
pub fn computeSlopeAndAssingSecpP(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    point0_alias: []const u8,
    point1_alias: []const u8,
    secp_p_comp: anytype,
) !void {
    var secp_p = try Int.initSet(allocator, secp_p_comp);
    {
        // block for clear errdefer deinit
        errdefer secp_p.deinit();
        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }

    try computeSlope(
        allocator,
        vm,
        exec_scopes,
        ids_data,
        ap_tracking,
        point0_alias,
        point1_alias,
    );
}

pub fn computeSlope(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    point0_alias: []const u8,
    point1_alias: []const u8,
) !void {
    //ids.point0
    const point0 = try EcPoint.fromVarName(point0_alias, vm, ids_data, ap_tracking);
    //ids.point1
    const point1 = try EcPoint.fromVarName(point1_alias, vm, ids_data, ap_tracking);

    var p0x = try point0.x.pack86(allocator);
    defer p0x.deinit();
    var p1x = try point1.x.pack86(allocator);
    defer p1x.deinit();

    var p0y = try point0.y.pack86(allocator);
    defer p0y.deinit();

    var p1y = try point1.y.pack86(allocator);
    defer p1y.deinit();

    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    var value = try lineSlope(allocator, .{ p0x, p0y }, .{ p1x, p1y }, secp_p);
    errdefer value.deinit();

    var slope = try value.clone();
    errdefer slope.deinit();
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
}

// Implements hint:
// %{from starkware.cairo.common.cairo_secp.secp_utils import pack

// slope = pack(ids.slope, PRIME)
// x0 = pack(ids.point0.x, PRIME)
// x1 = pack(ids.point1.x, PRIME)
// y0 = pack(ids.point0.y, PRIME)

// value = new_x = (pow(slope, 2, SECP_P) - x0 - x1) % SECP_P
// %}
pub fn squareSlopeMinusXs(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    const point0 = try EcPoint.fromVarName("point0", vm, ids_data, ap_tracking);
    const point1 = try EcPoint.fromVarName("point1", vm, ids_data, ap_tracking);

    var slope = try (try BigInt3.fromVarName("slope", vm, ids_data, ap_tracking)).pack86(allocator);
    errdefer slope.deinit();

    var x0 = try point0.x.pack86(allocator);
    errdefer x0.deinit();
    var x1 = try point1.x.pack86(allocator);
    errdefer x1.deinit();
    var y0 = try point0.y.pack86(allocator);
    errdefer y0.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.pow(&slope, 2);
    try tmp.sub(&tmp, &x0);
    try tmp.sub(&tmp, &x1);

    var value = try Int.init(allocator);
    errdefer value.deinit();

    try tmp.divFloor(&value, &tmp, &secp_p);

    var new_x = try value.clone();
    errdefer new_x.deinit();

    try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
    try exec_scopes.assignOrUpdateVariable("x0", .{ .big_int = x0 });
    try exec_scopes.assignOrUpdateVariable("x1", .{ .big_int = x1 });
    try exec_scopes.assignOrUpdateVariable("y0", .{ .big_int = y0 });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("new_x", .{ .big_int = new_x });
}

pub fn ecDoubleAssignNewXV2(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    point_alias: []const u8,
) !void {
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    try ecDoubleAssignNewX(allocator, vm, exec_scopes, ids_data, ap_tracking, secp_p, point_alias);
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

//     slope = pack(ids.slope, PRIME)
//     x = pack(ids.point.x, PRIME)
//     y = pack(ids.point.y, PRIME)

//     value = new_x = (pow(slope, 2, SECP_P) - 2 * x) % SECP_P
// %}
pub fn ecDoubleAssignNewX(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    secp_p_comp: anytype,
    point_alias: []const u8,
) !void {
    var secp_p = try Int.init(allocator);

    {
        errdefer secp_p.deinit();

        if (std.meta.hasFn(@TypeOf(secp_p_comp), "toConst")) {
            // if big int
            try secp_p.copy(secp_p_comp.toConst());
        } else if (@TypeOf(secp_p_comp) == comptime_int) {
            // just comptime int
            try secp_p.set(secp_p_comp);
        }

        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }
    //ids.slope
    const slope_big_int3 = try BigInt3.fromVarName("slope", vm, ids_data, ap_tracking);
    //ids.point
    const point = try EcPoint.fromVarName(point_alias, vm, ids_data, ap_tracking);

    var slope = try slope_big_int3.pack86(allocator);
    errdefer slope.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.divFloor(&slope, &slope, &secp_p);

    var x = try point.x.pack86(allocator);
    errdefer x.deinit();

    try tmp.divFloor(&x, &x, &secp_p);
    var y = try point.y.pack86(allocator);
    errdefer y.deinit();

    try tmp.divFloor(&y, &y, &secp_p);

    var value = try Int.init(allocator);
    errdefer value.deinit();

    try value.pow(&slope, 2);
    try tmp.shiftLeft(&x, 1);
    try value.sub(&value, &tmp);
    try tmp.divFloor(&value, &value, &secp_p);

    var new_x = try value.clone();
    errdefer new_x.deinit();

    //Assign variables to vm scope
    try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
    try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = x });
    try exec_scopes.assignOrUpdateVariable("y", .{ .big_int = y });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("new_x", .{ .big_int = new_x });
}

// Implements hint:
// %{ value = new_y = (slope * (x - new_x) - y) % SECP_P %}
pub fn ecDoubleAssignNewY(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    //Get variables from vm scope
    const slope = try exec_scopes.getValue(Int, "slope");
    const x = try exec_scopes.getValue(Int, "x");
    const new_x = try exec_scopes.getValue(Int, "new_x");
    const y = try exec_scopes.getValue(Int, "y");
    const secp_p = try exec_scopes.getValue(Int, "SECP_P");

    var value = try Int.init(allocator);
    errdefer value.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    try tmp.sub(&x, &new_x);
    try tmp.mul(&tmp, &slope);
    try value.sub(&tmp, &y);
    try tmp.divFloor(&value, &value, &secp_p);

    var new_y = try value.clone();
    errdefer new_y.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("new_y", .{ .big_int = new_y });
}

// Implements hint:
// %{
//     from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack

//     slope = pack(ids.slope, PRIME)
//     x0 = pack(ids.point0.x, PRIME)
//     x1 = pack(ids.point1.x, PRIME)
//     y0 = pack(ids.point0.y, PRIME)

//     value = new_x = (pow(slope, 2, SECP_P) - x0 - x1) % SECP_P
// %}
pub fn fastEcAddAssignNewX(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    secp_p_comp: anytype,
    point0_alias: []const u8,
    point1_alias: []const u8,
) !void {
    var secp_p = try Int.initSet(allocator, secp_p_comp);
    {
        errdefer secp_p.deinit();

        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }

    //ids.slope
    const slope3 = try BigInt3.fromVarName("slope", vm, ids_data, ap_tracking);
    //ids.point0
    const point0 = try EcPoint.fromVarName(point0_alias, vm, ids_data, ap_tracking);
    //ids.point1.x
    const point1 = try EcPoint.fromVarName(point1_alias, vm, ids_data, ap_tracking);

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var slope = try slope3.pack86(allocator);
    errdefer slope.deinit();

    var x0 = try point0.x.pack86(allocator);
    errdefer x0.deinit();

    var x1 = try point1.x.pack86(allocator);
    defer x1.deinit();

    var y0 = try point0.y.pack86(allocator);
    errdefer y0.deinit();

    try tmp.divFloor(&slope, &slope, &secp_p);
    try tmp.divFloor(&x0, &x0, &secp_p);
    try tmp.divFloor(&x1, &x1, &secp_p);
    try tmp.divFloor(&y0, &y0, &secp_p);

    var value = try Int.init(allocator);
    errdefer value.deinit();

    try value.mul(&slope, &slope);
    try value.sub(&value, &x0);
    try value.sub(&value, &x1);

    try tmp.divFloor(&value, &value, &secp_p);

    var new_x = try value.clone();
    errdefer new_x.deinit();

    //Assign variables to vm scope
    try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
    try exec_scopes.assignOrUpdateVariable("x0", .{ .big_int = x0 });
    try exec_scopes.assignOrUpdateVariable("y0", .{ .big_int = y0 });
    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("new_x", .{ .big_int = new_x });
}

// Implements hint:
// %{ value = new_y = (slope * (x0 - new_x) - y0) % SECP_P %}
pub fn fastEcAddAssignNewY(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    //Get variables from vm scope
    const slope = try exec_scopes.getValue(Int, "slope");
    const x0 = try exec_scopes.getValue(Int, "x0");
    const new_x = try exec_scopes.getValue(Int, "new_x");
    const y0 = try exec_scopes.getValue(Int, "y0");
    const SECP_P = try exec_scopes.getValue(Int, "SECP_P");

    var tmp = try Int.init(allocator);
    defer tmp.deinit();

    var value = try Int.init(allocator);
    errdefer value.deinit();

    try value.sub(&x0, &new_x);
    try value.mul(&slope, &value);
    try value.sub(&value, &y0);

    try tmp.divFloor(&value, &value, &SECP_P);

    var new_y = try value.clone();
    errdefer new_y.deinit();

    try exec_scopes.assignOrUpdateVariable("value", .{ .big_int = value });
    try exec_scopes.assignOrUpdateVariable("new_y", .{ .big_int = new_y });
}

// Implements hint:
// %{ memory[ap] = (ids.scalar % PRIME) % 2 %}
pub fn ecMulInner(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    //(ids.scalar % PRIME) % 2
    var scalar = try hint_utils.getIntegerFromVarName("scalar", vm, ids_data, ap_tracking);
    scalar = scalar.modFloor2(Felt252.two());

    try hint_utils.insertValueIntoAp(allocator, vm, MaybeRelocatable.fromFelt(scalar));
}

// Implements hint:
// %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_ALPHA as ALPHA %}
pub fn importSecp256r1Alpha(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    var secp = try Int.initSet(allocator, secp_utils.SECP256R1_ALPHA);
    errdefer secp.deinit();

    try exec_scopes.assignOrUpdateVariable("ALPHA", .{ .big_int = secp });
}

// Implements hint:
// %{ from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_N as N %}
pub fn importSecp256r1N(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    var secp_p = try Int.initSet(allocator, secp_utils.SECP256R1_N);
    errdefer secp_p.deinit();

    try exec_scopes.assignOrUpdateVariable("N", .{ .big_int = secp_p });
}

// Implements hint:
// %{
// from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_P as SECP_P
// %}
pub fn importSecp256r1P(allocator: std.mem.Allocator, exec_scopes: *ExecutionScopes) !void {
    var secp_p = try Int.initSet(allocator, secp_utils.SECP256R1_P);
    errdefer secp_p.deinit();

    try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
}

pub fn nPairBits(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    result_name: []const u8,
    comptime number_of_pairs: u32,
) !void {
    const scalar_v = try hint_utils.getIntegerFromVarName("scalar_v", vm, ids_data, ap_tracking);
    const scalar_u = try hint_utils.getIntegerFromVarName("scalar_u", vm, ids_data, ap_tracking);
    const m = (try hint_utils.getIntegerFromVarName("m", vm, ids_data, ap_tracking)).toInt(usize) catch 253;

    // If m is too high the shift result will always be zero
    if (m >= 253) {
        return hint_utils.insertValueFromVarName(allocator, result_name, MaybeRelocatable.fromFelt(Felt252.zero()), vm, ids_data, ap_tracking);
    }

    if (m + 1 < number_of_pairs) {
        return HintError.NPairBitsTooLowM;
    }

    var scalar_v_big = try Int.initSet(allocator, scalar_v.toU256());
    defer scalar_v_big.deinit();

    var scalar_u_big = try Int.initSet(allocator, scalar_u.toU256());
    defer scalar_u_big.deinit();

    var result = try Int.initSet(allocator, 0);
    defer result.deinit();

    var tmp = try Int.init(allocator);
    defer tmp.deinit();
    var tmp2 = try Int.init(allocator);
    defer tmp2.deinit();

    var one = try Int.initSet(allocator, 1);
    defer one.deinit();

    // Each step, fetches the bits in mth position for v and u,
    // and appends them to the accumulator. i.e:
    //         10
    //         ↓↓
    //  1010101__ -> 101010110
    inline for (0..number_of_pairs) |i| {
        try tmp.shiftRight(&scalar_u_big, m - (number_of_pairs - 1 - i));
        try tmp.bitAnd(&tmp, &one);

        try tmp2.set(std.math.pow(usize, 2, i * number_of_pairs));

        try tmp.mul(&tmp, &tmp2);

        try result.add(&result, &tmp);

        try tmp.shiftRight(&scalar_v_big, m - (number_of_pairs - 1 - i));
        try tmp.bitAnd(&tmp, &one);

        try tmp2.set(std.math.pow(usize, 2, i * number_of_pairs + 1));

        try tmp.mul(&tmp, &tmp2);

        try result.add(&result, &tmp);
    }
    //     ids.quad_bit = (
    //         8 * ((ids.scalar_v >> ids.m) & 1)
    //         + 4 * ((ids.scalar_u >> ids.m) & 1)
    //         + 2 * ((ids.scalar_v >> (ids.m - 1)) & 1)
    //         + ((ids.scalar_u >> (ids.m - 1)) & 1)
    //     )
    // %{ ids.dibit = ((ids.scalar_u >> ids.m) & 1) + 2 * ((ids.scalar_v >> ids.m) & 1) %}

    try hint_utils
        .insertValueFromVarName(
        allocator,
        result_name,
        MaybeRelocatable.fromFelt(try fromBigInt(allocator, result)),
        vm,
        ids_data,
        ap_tracking,
    );
}

// Implements hint:
// %{
//     ids.quad_bit = (
//         8 * ((ids.scalar_v >> ids.m) & 1)
//         + 4 * ((ids.scalar_u >> ids.m) & 1)
//         + 2 * ((ids.scalar_v >> (ids.m - 1)) & 1)
//         + ((ids.scalar_u >> (ids.m - 1)) & 1)
//     )
// %}
pub fn quadBit(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    return nPairBits(allocator, vm, ids_data, ap_tracking, "quad_bit", 2);
}

// Implements hint:
// %{ ids.dibit = ((ids.scalar_u >> ids.m) & 1) + 2 * ((ids.scalar_v >> ids.m) & 1) %}
pub fn diBit(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    return nPairBits(allocator, vm, ids_data, ap_tracking, "dibit", 1);
}

test "SecpEcUtils: diBit ok" {
    const hint_code = hint_codes.DI_BIT;
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Insert ids.scalar into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0b10101111001110000} },
        .{ .{ 1, 1 }, .{0b101101000111011111100} },
        .{ .{ 1, 2 }, .{3} },
    });

    // Initialize RunContext
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 4;
    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar_u",
        "scalar_v",
        "m",
        "dibit",
    });
    defer ids_data.deinit();

    // Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        undefined,
    );

    // Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{2} },
    });
}

test "SecpEcUtils: quadBit ok" {
    const hint_code = hint_codes.QUAD_BIT;
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Insert ids.scalar into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{89712} },
        .{ .{ 1, 1 }, .{1478396} },
        .{ .{ 1, 2 }, .{4} },
    });

    // Initialize RunContext
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 4;
    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar_u",
        "scalar_v",
        "m",
        "quad_bit",
    });
    defer ids_data.deinit();

    // Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        undefined,
    );

    // Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{14} },
    });
}

test "SecpEcUtils: diBit zero ok" {
    const hint_code = hint_codes.DI_BIT;
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Insert ids.scalar into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0b00} },
        .{ .{ 1, 1 }, .{0b01} },
        .{ .{ 1, 2 }, .{0} },
    });

    // Initialize RunContext
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 4;
    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar_u",
        "scalar_v",
        "m",
        "dibit",
    });
    defer ids_data.deinit();

    // Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        undefined,
    );

    // Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{0b10} },
    });
}

test "SecpEcUtils: diBit max m ok" {
    const hint_code = hint_codes.DI_BIT;
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Insert ids.scalar into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{89712} },
        .{ .{ 1, 1 }, .{1478396} },
        .{ .{ 1, 2 }, .{std.math.maxInt(i128)} },
    });

    // Initialize RunContext
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 4;
    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar_u",
        "scalar_v",
        "m",
        "dibit",
    });
    defer ids_data.deinit();

    // Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        undefined,
    );

    // Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{0} },
    });
}

test "SecpEcUtils: quadBit for m 1 ok" {
    const hint_code = hint_codes.QUAD_BIT;
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Insert ids.scalar into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{89712} },
        .{ .{ 1, 1 }, .{1478396} },
        .{ .{ 1, 2 }, .{1} },
    });

    // Initialize RunContext
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 4;
    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar_u",
        "scalar_v",
        "m",
        "quad_bit",
    });
    defer ids_data.deinit();

    // Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        undefined,
    );

    // Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{0} },
    });
}

test "SecpEcUtils: quadBit for max m ok" {
    const hint_code = hint_codes.QUAD_BIT;
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Insert ids.scalar into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{89712} },
        .{ .{ 1, 1 }, .{1478396} },
        .{ .{ 1, 2 }, .{std.math.maxInt(i128)} },
    });

    // Initialize RunContext
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 4;
    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar_u",
        "scalar_v",
        "m",
        "quad_bit",
    });
    defer ids_data.deinit();

    // Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        undefined,
    );

    // Check hint memory inserts
    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 3 }, .{0} },
    });
}

test "SecpEcUtils: quadBit for m 0" {
    const hint_code = hint_codes.QUAD_BIT;
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // Insert ids.scalar into memory
    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{0b1010101} },
        .{ .{ 1, 1 }, .{0b1010101} },
        .{ .{ 1, 2 }, .{0} },
    });

    // Initialize RunContext
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 4;
    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar_u",
        "scalar_v",
        "m",
        "quad_bit",
    });
    defer ids_data.deinit();

    // Execute the hint
    try std.testing.expectError(HintError.NPairBitsTooLowM, testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        undefined,
    ));
}

test "SecpEcUtils: run ecNegateOk" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\n\ny = pack(ids.point.y, PRIME) % SECP_P\n# The modulo operation in python always returns a nonnegative number.\nvalue = (-y) % SECP_P";
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 3 }, .{2645} },
        .{ .{ 1, 4 }, .{454} },
        .{ .{ 1, 5 }, .{206} },
    });

    //Initialize fp
    vm.run_context.fp = 1;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "point",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();
    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    var exp_value = try Int.initSet(std.testing.allocator, 115792089237316195423569751828682367333329274433232027476421668138471189901786);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
}

test "SecpEcUtils: run ecNegateEmbededSecp ok" {
    const hint_code = hint_codes.EC_NEGATE_EMBEDDED_SECP;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 3 }, .{2645} },
        .{ .{ 1, 4 }, .{454} },
        .{ .{ 1, 5 }, .{206} },
    });

    //Initialize fp
    vm.run_context.fp = 1;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "point",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    const y = (206 << (86 * 2)) + (454 << 86) + 2645;
    const minus_y = (1 << 255) - 19 - y;

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    var exp_value = try Int.initSet(std.testing.allocator, minus_y);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
}

test "SecpEcUtils: run computeDoublingSlope ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\nfrom starkware.python.math_utils import ec_double_slope\n\n# Compute the slope.\nx = pack(ids.point.x, PRIME)\ny = pack(ids.point.y, PRIME)\nvalue = slope = ec_double_slope(point=(x, y), alpha=0, p=SECP_P)";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{614323} },
        .{ .{ 1, 1 }, .{5456867} },
        .{ .{ 1, 2 }, .{101208} },
        .{ .{ 1, 3 }, .{773712524} },
        .{ .{ 1, 4 }, .{77371252} },
        .{ .{ 1, 5 }, .{5298795} },
    });

    //Initialize fp
    vm.run_context.fp = 1;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "point",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");
    var exp_value = try Int.initSet(std.testing.allocator, 40442433062102151071094722250325492738932110061897694430475034100717288403728);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
    try std.testing.expect(act_slope.eql(exp_value));
}

test "SecpEcUtils: run computeDoublingSlopeV2 ok" {
    const hint_code = hint_codes.EC_DOUBLE_SLOPE_V2;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{512} },
        .{ .{ 1, 1 }, .{2412} },
        .{ .{ 1, 2 }, .{133} },
        .{ .{ 1, 3 }, .{64} },
        .{ .{ 1, 4 }, .{0} },
        .{ .{ 1, 5 }, .{6546} },
    });

    //Initialize fp
    vm.run_context.fp = 1;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "point",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");
    var exp_value = try Int.initSet(std.testing.allocator, 48268701472940295594394094960749868325610234644833445333946260403470540790234);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
    try std.testing.expect(act_slope.eql(exp_value));

    try exp_value.set(secp_utils.SECP_P_V2);

    const act_secp_p = try exec_scopes.getValue(Int, "SECP_P");

    try std.testing.expect(act_secp_p.eql(exp_value));
}

test "SecpEcUtils: compute doubling slope wdivmode ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\nfrom starkware.python.math_utils import div_mod\n\n# Compute the slope.\nx = pack(ids.pt.x, PRIME)\ny = pack(ids.pt.y, PRIME)\nvalue = slope = div_mod(3 * x ** 2, 2 * y, SECP_P)";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{614323} },
        .{ .{ 1, 1 }, .{5456867} },
        .{ .{ 1, 2 }, .{101208} },
        .{ .{ 1, 3 }, .{773712524} },
        .{ .{ 1, 4 }, .{77371252} },
        .{ .{ 1, 5 }, .{5298795} },
    });

    //Initialize fp
    vm.run_context.fp = 1;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "pt",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");
    var exp_value = try Int.initSet(std.testing.allocator, 40442433062102151071094722250325492738932110061897694430475034100717288403728);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
    try std.testing.expect(act_slope.eql(exp_value));
}

test "SecpEcUtils: compute doubling slope with custom consts ok" {
    const hint_code = hint_codes.EC_DOUBLE_SLOPE_EXTERNAL_CONSTS;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{614323} },
        .{ .{ 1, 1 }, .{5456867} },
        .{ .{ 1, 2 }, .{101208} },
        .{ .{ 1, 3 }, .{773712524} },
        .{ .{ 1, 4 }, .{77371252} },
        .{ .{ 1, 5 }, .{5298795} },
    });

    //Initialize fp
    vm.run_context.fp = 1;
    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "point",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    {
        // we need this block, because err deinit of bigint we need only if we no assign data
        var SECP256R1_P = try Int.initSet(std.testing.allocator, secp_utils.SECP256R1_P);
        errdefer SECP256R1_P.deinit();

        var SECP256R1_ALPHA = try Int.initSet(std.testing.allocator, secp_utils.SECP256R1_ALPHA);
        errdefer SECP256R1_ALPHA.deinit();

        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = SECP256R1_P });
        try exec_scopes.assignOrUpdateVariable("ALPHA", .{ .big_int = SECP256R1_ALPHA });
    }

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");

    var exp_value = try Int.initSet(std.testing.allocator, 99065496658741969395000079476826955370154683653966841736214499259699304892273);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
    try std.testing.expect(act_slope.eql(exp_value));
}

test "SecpEcUtils: compute slope ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\nfrom starkware.python.math_utils import line_slope\n\n# Compute the slope.\nx0 = pack(ids.point0.x, PRIME)\ny0 = pack(ids.point0.y, PRIME)\nx1 = pack(ids.point1.x, PRIME)\ny1 = pack(ids.point1.y, PRIME)\nvalue = slope = line_slope(point1=(x0, y0), point2=(x1, y1), p=SECP_P)";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{134} },
        .{ .{ 1, 1 }, .{5123} },
        .{ .{ 1, 2 }, .{140} },
        .{ .{ 1, 3 }, .{1232} },
        .{ .{ 1, 4 }, .{4652} },
        .{ .{ 1, 5 }, .{720} },
        .{ .{ 1, 6 }, .{156} },
        .{ .{ 1, 7 }, .{6545} },
        .{ .{ 1, 8 }, .{100010} },
        .{ .{ 1, 9 }, .{1123} },
        .{ .{ 1, 10 }, .{1325} },
        .{ .{ 1, 11 }, .{910} },
    });

    //Initialize fp
    vm.run_context.fp = 14;
    //Create hint_data

    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    try ids_data.put("point0", HintReference.initSimple(-14));
    try ids_data.put("point1", HintReference.initSimple(-8));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");

    var exp_value = try Int.initSet(std.testing.allocator, 41419765295989780131385135514529906223027172305400087935755859001910844026631);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
    try std.testing.expect(act_slope.eql(exp_value));
}

test "SecpEcUtils: compute slope v2 ok" {
    const hint_code = hint_codes.COMPUTE_SLOPE_V2;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{512} },
            .{ .{ 1, 1 }, .{2412} },
            .{ .{ 1, 2 }, .{133} },
            .{ .{ 1, 3 }, .{64} },
            .{ .{ 1, 4 }, .{0} },
            .{ .{ 1, 5 }, .{6546} },
            .{ .{ 1, 6 }, .{7} },
            .{ .{ 1, 7 }, .{8} },
            .{ .{ 1, 8 }, .{123} },
            .{ .{ 1, 9 }, .{1} },
            .{ .{ 1, 10 }, .{7} },
            .{ .{ 1, 11 }, .{465} },
        },
    );

    //Initialize fp
    vm.run_context.fp = 14;
    //Create hint_data

    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    try ids_data.put("point0", HintReference.initSimple(-14));
    try ids_data.put("point1", HintReference.initSimple(-8));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");

    var exp_value = try Int.initSet(std.testing.allocator, 39376930140709393693483102164172662915882483986415749881375763965703119677959);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
    try std.testing.expect(act_slope.eql(exp_value));
}

test "SecpEcUtils: compute slope wdivmod ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\nfrom starkware.python.math_utils import div_mod\n\n# Compute the slope.\nx0 = pack(ids.pt0.x, PRIME)\ny0 = pack(ids.pt0.y, PRIME)\nx1 = pack(ids.pt1.x, PRIME)\ny1 = pack(ids.pt1.y, PRIME)\nvalue = slope = div_mod(y0 - y1, x0 - x1, SECP_P)";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{134} },
            .{ .{ 1, 1 }, .{5123} },
            .{ .{ 1, 2 }, .{140} },
            .{ .{ 1, 3 }, .{1232} },
            .{ .{ 1, 4 }, .{4652} },
            .{ .{ 1, 5 }, .{720} },
            .{ .{ 1, 6 }, .{156} },
            .{ .{ 1, 7 }, .{6545} },
            .{ .{ 1, 8 }, .{100010} },
            .{ .{ 1, 9 }, .{1123} },
            .{ .{ 1, 10 }, .{1325} },
            .{ .{ 1, 11 }, .{910} },
        },
    );

    //Initialize fp
    vm.run_context.fp = 14;
    //Create hint_data

    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    try ids_data.put("pt0", HintReference.initSimple(-14));
    try ids_data.put("pt1", HintReference.initSimple(-8));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");

    var exp_value = try Int.initSet(std.testing.allocator, 41419765295989780131385135514529906223027172305400087935755859001910844026631);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
    try std.testing.expect(act_slope.eql(exp_value));
}

test "SecpEcUtils: ec double assign new x ok" {
    const hint_code = hint_codes.EC_DOUBLE_ASSIGN_NEW_X_V1;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{134} },
            .{ .{ 1, 1 }, .{5123} },
            .{ .{ 1, 2 }, .{140} },
            .{ .{ 1, 3 }, .{1232} },
            .{ .{ 1, 4 }, .{4652} },
            .{ .{ 1, 5 }, .{720} },
            .{ .{ 1, 6 }, .{44186171158942157784255469} },
            .{ .{ 1, 7 }, .{54173758974262696047492534} },
            .{ .{ 1, 8 }, .{8106299688661572814170174} },
        },
    );

    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data

    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    try ids_data.put("point", HintReference.initSimple(-10));
    try ids_data.put("slope", HintReference.initSimple(-4));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");

    var exp_value = try Int.initSet(std.testing.allocator, 59479631769792988345961122678598249997181612138456851058217178025444564264149);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));

    var exp_slope = try Int.initSet(std.testing.allocator, 48526828616392201132917323266456307435009781900148206102108934970258721901549);
    defer exp_slope.deinit();

    try std.testing.expect(act_slope.eql(exp_slope));

    const act_x = try exec_scopes.getValue(Int, "x");

    var exp_x = try Int.initSet(std.testing.allocator, 838083498911032969414721426845751663479194726707495046);
    defer exp_x.deinit();

    try std.testing.expect(act_x.eql(exp_x));

    const act_y = try exec_scopes.getValue(Int, "y");

    var exp_y = try Int.initSet(std.testing.allocator, 4310143708685312414132851373791311001152018708061750480);
    defer exp_y.deinit();

    try std.testing.expect(act_y.eql(exp_y));

    const act_new_x = try exec_scopes.getValue(Int, "new_x");

    var exp_new_x = try Int.initSet(std.testing.allocator, 59479631769792988345961122678598249997181612138456851058217178025444564264149);
    defer exp_new_x.deinit();

    try std.testing.expect(act_new_x.eql(exp_new_x));
}

test "SecpEcUtils: ec double assign new x v2 ok" {
    const hint_code = hint_codes.EC_DOUBLE_ASSIGN_NEW_X_V2;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{134} },
            .{ .{ 1, 1 }, .{5123} },
            .{ .{ 1, 2 }, .{140} },
            .{ .{ 1, 3 }, .{1232} },
            .{ .{ 1, 4 }, .{4652} },
            .{ .{ 1, 5 }, .{720} },
            .{ .{ 1, 6 }, .{44186171158942157784255469} },
            .{ .{ 1, 7 }, .{54173758974262696047492534} },
            .{ .{ 1, 8 }, .{8106299688661572814170174} },
        },
    );

    //Initialize fp
    vm.run_context.fp = 10;
    //Create hint_data

    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    try ids_data.put("point", HintReference.initSimple(-10));
    try ids_data.put("slope", HintReference.initSimple(-4));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    var secp_p = try Int.initSet(std.testing.allocator, secp_utils.SECP_P);
    {
        errdefer secp_p.deinit();
        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }
    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");
    const act_slope = try exec_scopes.getValue(Int, "slope");

    var exp_value = try Int.initSet(std.testing.allocator, 59479631769792988345961122678598249997181612138456851058217178025444564264149);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));

    var exp_slope = try Int.initSet(std.testing.allocator, 48526828616392201132917323266456307435009781900148206102108934970258721901549);
    defer exp_slope.deinit();

    try std.testing.expect(act_slope.eql(exp_slope));

    const act_x = try exec_scopes.getValue(Int, "x");

    var exp_x = try Int.initSet(std.testing.allocator, 838083498911032969414721426845751663479194726707495046);
    defer exp_x.deinit();

    try std.testing.expect(act_x.eql(exp_x));

    const act_y = try exec_scopes.getValue(Int, "y");

    var exp_y = try Int.initSet(std.testing.allocator, 4310143708685312414132851373791311001152018708061750480);
    defer exp_y.deinit();

    try std.testing.expect(act_y.eql(exp_y));

    const act_new_x = try exec_scopes.getValue(Int, "new_x");

    var exp_new_x = try Int.initSet(std.testing.allocator, 59479631769792988345961122678598249997181612138456851058217178025444564264149);
    defer exp_new_x.deinit();

    try std.testing.expect(act_new_x.eql(exp_new_x));
}

test "SecpEcUtils: ec double assign new y ok" {
    const hint_code = hint_codes.EC_DOUBLE_ASSIGN_NEW_Y;

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    //Create hint_data
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    {
        var slope = try Int.initSet(std.testing.allocator, 48526828616392201132917323266456307435009781900148206102108934970258721901549);
        errdefer slope.deinit();

        try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
    }

    {
        var x = try Int.initSet(std.testing.allocator, 838083498911032969414721426845751663479194726707495046);
        errdefer x.deinit();

        try exec_scopes.assignOrUpdateVariable("x", .{ .big_int = x });
    }

    {
        var y = try Int.initSet(std.testing.allocator, 4310143708685312414132851373791311001152018708061750480);
        errdefer y.deinit();

        try exec_scopes.assignOrUpdateVariable("y", .{ .big_int = y });
    }

    {
        var new_x = try Int.initSet(std.testing.allocator, 59479631769792988345961122678598249997181612138456851058217178025444564264149);
        errdefer new_x.deinit();

        try exec_scopes.assignOrUpdateVariable("new_x", .{ .big_int = new_x });
    }
    {
        var SECP_P = try Int.initSet(std.testing.allocator, secp_utils.SECP_P);
        errdefer SECP_P.deinit();

        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = SECP_P });
    }

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");

    var exp_value = try Int.initSet(std.testing.allocator, 7948634220683381957329555864604318996476649323793038777651086572350147290350);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));

    const act_y = try exec_scopes.getValue(Int, "new_y");

    var exp_y = try Int.initSet(std.testing.allocator, 7948634220683381957329555864604318996476649323793038777651086572350147290350);
    defer exp_y.deinit();

    try std.testing.expect(act_y.eql(exp_y));
}

test "SecpEcUtils: fast ec add assign new x ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import SECP_P, pack\n\nslope = pack(ids.slope, PRIME)\nx0 = pack(ids.point0.x, PRIME)\nx1 = pack(ids.point1.x, PRIME)\ny0 = pack(ids.point0.y, PRIME)\n\nvalue = new_x = (pow(slope, 2, SECP_P) - x0 - x1) % SECP_P";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{89712} },
            .{ .{ 1, 1 }, .{56} },
            .{ .{ 1, 2 }, .{1233409} },
            .{ .{ 1, 3 }, .{980126} },
            .{ .{ 1, 4 }, .{10} },
            .{ .{ 1, 5 }, .{8793} },
            .{ .{ 1, 6 }, .{1235216451} },
            .{ .{ 1, 7 }, .{5967} },
            .{ .{ 1, 8 }, .{2171381} },
            .{ .{ 1, 9 }, .{67470097831679799377177424} },
            .{ .{ 1, 10 }, .{43370026683122492246392730} },
            .{ .{ 1, 11 }, .{16032182557092050689870202} },
        },
    );

    //Initialize fp
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 20;
    vm.run_context.fp = 15;
    //Create hint_data

    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    try ids_data.put("point0", HintReference.initSimple(-15));
    try ids_data.put("point1", HintReference.initSimple(-9));
    try ids_data.put("slope", HintReference.initSimple(-6));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");

    var exp_value = try Int.initSet(std.testing.allocator, 8891838197222656627233627110766426698842623939023296165598688719819499152657);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));

    const act_new_x = try exec_scopes.getValue(Int, "new_x");

    try std.testing.expect(act_new_x.eql(exp_value));
}

test "SecpEcUtils: fast ec add assign new y ok" {
    const hint_code = "value = new_y = (slope * (x0 - new_x) - y0) % SECP_P";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    {
        var slope = try Int.initSet(std.testing.allocator, 48526828616392201132917323266456307435009781900148206102108934970258721901549);
        errdefer slope.deinit();

        try exec_scopes.assignOrUpdateVariable("slope", .{ .big_int = slope });
    }

    {
        var x = try Int.initSet(std.testing.allocator, 838083498911032969414721426845751663479194726707495046);
        errdefer x.deinit();

        try exec_scopes.assignOrUpdateVariable("x0", .{ .big_int = x });
    }

    {
        var y = try Int.initSet(std.testing.allocator, 4310143708685312414132851373791311001152018708061750480);
        errdefer y.deinit();

        try exec_scopes.assignOrUpdateVariable("y0", .{ .big_int = y });
    }

    {
        var new_x = try Int.initSet(std.testing.allocator, 59479631769792988345961122678598249997181612138456851058217178025444564264149);
        errdefer new_x.deinit();

        try exec_scopes.assignOrUpdateVariable("new_x", .{ .big_int = new_x });
    }
    {
        var SECP_P = try Int.initSet(std.testing.allocator, secp_utils.SECP_P);
        errdefer SECP_P.deinit();

        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = SECP_P });
    }

    //Create hint_data
    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");

    var exp_value = try Int.initSet(std.testing.allocator, 7948634220683381957329555864604318996476649323793038777651086572350147290350);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));

    const act_new_y = try exec_scopes.getValue(Int, "new_y");

    try std.testing.expect(act_new_y.eql(exp_value));
}

test "SecpEcUtils: ecMulInner ok" {
    const hint_code = "memory[ap] = (ids.scalar % PRIME) % 2";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{89712} },
    });

    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 2;
    vm.run_context.fp = 1;

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "scalar",
    });
    defer ids_data.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    try testing_utils.checkMemory(vm.segments.memory, .{
        .{ .{ 1, 2 }, .{0} },
    });
}

test "SecpEcUtils: ec point from var name ok" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{4} },
        .{ .{ 1, 4 }, .{5} },
        .{ .{ 1, 5 }, .{6} },
    });

    vm.run_context.fp = 1;

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "e",
    });
    defer ids_data.deinit();

    const e = try EcPoint.fromVarName("e", &vm, ids_data, .{});

    try std.testing.expectEqual(Felt252.one(), e.x.limbs[0]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 2), e.x.limbs[1]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 3), e.x.limbs[2]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 4), e.y.limbs[0]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 5), e.y.limbs[1]);
    try std.testing.expectEqual(Felt252.fromInt(u8, 6), e.y.limbs[2]);
}

test "SecpEcUtils: ec point from var name missing number" {
    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{1} },
        .{ .{ 1, 1 }, .{2} },
        .{ .{ 1, 2 }, .{3} },
        .{ .{ 1, 3 }, .{4} },
    });

    vm.run_context.fp = 1;

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Create hint_data
    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "e",
    });
    defer ids_data.deinit();

    const e = EcPoint.fromVarName("e", &vm, ids_data, .{});

    try std.testing.expectError(HintError.IdentifierHasNoMember, e);
}

test "SecpEcUtils: import secp256r1 alpha ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp256r1_utils import SECP256R1_ALPHA as ALPHA";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    //Initialize fp

    vm.run_context.fp = 1;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "point",
    });
    defer ids_data.deinit();

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "ALPHA");

    var exp_value = try Int.initSet(std.testing.allocator, 115792089210356248762697446949407573530086143415290314195533631308867097853948);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));
}

test "SecpEcUtils: squareSlopeMinusX ok" {
    const hint_code = "from starkware.cairo.common.cairo_secp.secp_utils import pack\n\nslope = pack(ids.slope, PRIME)\nx0 = pack(ids.point0.x, PRIME)\nx1 = pack(ids.point1.x, PRIME)\ny0 = pack(ids.point0.y, PRIME)\n\nvalue = new_x = (pow(slope, 2, SECP_P) - x0 - x1) % SECP_P";

    var vm = try testing_utils.initVMWithRangeCheck(std.testing.allocator);
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    try vm.segments.memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 1, 0 }, .{89712} },
            .{ .{ 1, 1 }, .{56} },
            .{ .{ 1, 2 }, .{1233409} },
            .{ .{ 1, 3 }, .{980126} },
            .{ .{ 1, 4 }, .{10} },
            .{ .{ 1, 5 }, .{8793} },
            .{ .{ 1, 6 }, .{1235216451} },
            .{ .{ 1, 7 }, .{5967} },
            .{ .{ 1, 8 }, .{2171381} },
            .{ .{ 1, 9 }, .{67470097831679799377177424} },
            .{ .{ 1, 10 }, .{43370026683122492246392730} },
            .{ .{ 1, 11 }, .{16032182557092050689870202} },
        },
    );

    //Initialize fp
    vm.run_context.pc = Relocatable.init(0, 0);
    vm.run_context.ap = 20;
    vm.run_context.fp = 15;
    //Create hint_data

    var ids_data = std.StringHashMap(HintReference).init(std.testing.allocator);
    defer ids_data.deinit();

    try ids_data.put("point0", HintReference.initSimple(-15));
    try ids_data.put("point1", HintReference.initSimple(-9));
    try ids_data.put("slope", HintReference.initSimple(-6));

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    {
        var secp_p = try Int.initSet(std.testing.allocator, secp_utils.SECP_P);
        errdefer secp_p.deinit();

        try exec_scopes.assignOrUpdateVariable("SECP_P", .{ .big_int = secp_p });
    }

    //Execute the hint
    try testing_utils.runHint(
        std.testing.allocator,
        &vm,
        ids_data,
        hint_code,
        undefined,
        &exec_scopes,
    );

    //Check 'value' is defined in the vm scope
    const act_value = try exec_scopes.getValue(Int, "value");

    var exp_value = try Int.initSet(std.testing.allocator, 8891838197222656627233627110766426698842623939023296165598688719819499152657);
    defer exp_value.deinit();

    try std.testing.expect(act_value.eql(exp_value));

    const act_new_x = try exec_scopes.getValue(Int, "new_x");

    try std.testing.expect(act_new_x.eql(exp_value));
}
