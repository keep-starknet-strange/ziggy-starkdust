const std = @import("std");

const testing_utils = @import("testing_utils.zig");
const CoreVM = @import("../vm/core.zig");
const field_helper = @import("../math/fields/helper.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const fromBigInt = @import("../math/fields/starknet.zig").fromBigInt;
const STARKNET_PRIME = @import("../math/fields/fields.zig").STARKNET_PRIME;
const SIGNED_FELT_MAX = @import("../math/fields/fields.zig").SIGNED_FELT_MAX;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const CairoVM = CoreVM.CairoVM;
const hint_utils = @import("hint_utils.zig");
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const HintData = @import("hint_processor_def.zig").HintData;
const HintReference = @import("hint_processor_def.zig").HintReference;
const hint_codes = @import("builtin_hint_codes.zig");
const Allocator = std.mem.Allocator;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;

const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

pub const EcPoint = struct {
    x: Felt252,
    y: Felt252,

    pub fn fromVarName(
        name: []const u8,
        vm: *CairoVM,
        ids_data: std.StringHashMap(HintReference),
        ap_tracking: ApTracking,
    ) !EcPoint {
        const point_addr = try hint_utils.getRelocatableFromVarName(name, vm, ids_data, ap_tracking);

        return .{
            .x = try (vm.getFelt(point_addr) catch HintError.IdentifierHasNoMember),
            .y = try (vm.getFelt(try point_addr.addUint(1)) catch HintError.IdentifierHasNoMember),
        };
    }
};

// Implements hint:
// from starkware.crypto.signature.signature import ALPHA, BETA, FIELD_PRIME
// from starkware.python.math_utils import random_ec_point
// from starkware.python.utils import to_bytes

// # Define a seed for random_ec_point that's dependent on all the input, so that:
// #   (1) The added point s is deterministic.
// #   (2) It's hard to choose inputs for which the builtin will fail.
// seed = b"".join(map(to_bytes, [ids.p.x, ids.p.y, ids.m, ids.q.x, ids.q.y]))
// ids.s.x, ids.s.y = random_ec_point(FIELD_PRIME, ALPHA, BETA, seed)

pub fn randomEcPointHint(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const p = try EcPoint.fromVarName("p", vm, ids_data, ap_tracking);
    const q = try EcPoint.fromVarName("q", vm, ids_data, ap_tracking);
    const m = try hint_utils.getIntegerFromVarName("m", vm, ids_data, ap_tracking);

    // let bytes = [p.x, p.y, m, q.x, q.y]
    //     .iter()
    //     .flat_map(|x| x.to_bytes_be())
    //     .collect();

    var bytes: [@sizeOf(u256) * 5]u8 = undefined;

    @memcpy(bytes[0..@sizeOf(u256)], p.x.toBytesBe()[0..]);
    @memcpy(bytes[@sizeOf(u256) .. @sizeOf(u256) * 2], p.y.toBytesBe()[0..]);
    @memcpy(bytes[@sizeOf(u256) * 2 .. @sizeOf(u256) * 3], m.toBytesBe()[0..]);
    @memcpy(bytes[@sizeOf(u256) * 3 .. @sizeOf(u256) * 4], q.x.toBytesBe()[0..]);
    @memcpy(bytes[@sizeOf(u256) * 4 .. @sizeOf(u256) * 5], q.y.toBytesBe()[0..]);

    const s_addr = try hint_utils.getRelocatableFromVarName("s", vm, ids_data, ap_tracking);

    const x_y = try randomEcPointSeeded(allocator, bytes[0..]);
    try vm.insertInMemory(allocator, s_addr, MaybeRelocatable.fromFelt(x_y[0]));
    try vm.insertInMemory(allocator, try s_addr.addUint(1), MaybeRelocatable.fromFelt(x_y[1]));
}

// Returns a random non-zero point on the elliptic curve
//   y^2 = x^3 + alpha * x + beta (mod field_prime).
// The point is created deterministically from the seed.
fn randomEcPointSeeded(allocator: std.mem.Allocator, seed_bytes: []const u8) !struct { Felt252, Felt252 } {
    // Hash initial seed
    const hasher = std.crypto.hash.sha2.Sha256;

    var seed: [@sizeOf(u256)]u8 = undefined;
    hasher.hash(seed_bytes, &seed, .{});

    var buffer: [1]u8 = undefined;
    var hash_buffer: [@sizeOf(u256)]u8 = undefined;

    var tmp = try std.math.big.int.Managed.init(allocator);
    defer tmp.deinit();

    var tmp1 = try std.math.big.int.Managed.init(allocator);
    defer tmp1.deinit();

    for (0..100) |i| {
        // Calculate x
        std.mem.writeInt(u8, &buffer, @truncate(i), .little);

        var input = std.ArrayList(u8).init(allocator);
        defer input.deinit();

        try input.appendSlice(seed[1..]);

        try input.appendSlice(buffer[0..]);
        try input.appendNTimes(0, 10 - buffer.len);

        hasher.hash(input.items, &hash_buffer, .{});

        const x = std.mem.readInt(u256, &hash_buffer, .big);

        // const y_coef = std.math.pow(i32, -1, seed[0] & 1);

        // Calculate y
        if (recoverY(Felt252.fromInt(u256, x))) |y| {
            return .{
                Felt252.fromInt(u256, x),
                y,
            };
        }
    }

    return HintError.RandomEcPointNotOnCurve;
}

// Implements hint:
// from starkware.crypto.signature.signature import ALPHA, BETA, FIELD_PRIME
//     from starkware.python.math_utils import random_ec_point
//     from starkware.python.utils import to_bytes

//     n_elms = ids.len
//     assert isinstance(n_elms, int) and n_elms >= 0, \
//         f'Invalid value for len. Got: {n_elms}.'
//     if '__chained_ec_op_max_len' in globals():
//         assert n_elms <= __chained_ec_op_max_len, \
//             f'chained_ec_op() can only be used with len<={__chained_ec_op_max_len}. ' \
//             f'Got: n_elms={n_elms}.'

//     # Define a seed for random_ec_point that's dependent on all the input, so that:
//     #   (1) The added point s is deterministic.
//     #   (2) It's hard to choose inputs for which the builtin will fail.
//     seed = b"".join(
//         map(
//             to_bytes,
//             [
//                 ids.p.x,
//                 ids.p.y,
//                 *memory.get_range(ids.m, n_elms),
//                 *memory.get_range(ids.q.address_, 2 * n_elms),
//             ],
//         )
//     )
//     ids.s.x, ids.s.y = random_ec_point(FIELD_PRIME, ALPHA, BETA, seed)"
pub fn chainedEcOpRandomEcPointHint(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const n_elms_f = try hint_utils.getIntegerFromVarName("len", vm, ids_data, ap_tracking);

    if (n_elms_f.isZero() or (if (n_elms_f.toInt(usize) catch null == null) true else false))
        return HintError.InvalidLenValue;

    const n_elms = try n_elms_f.toInt(usize);
    const p = try EcPoint.fromVarName("p", vm, ids_data, ap_tracking);
    const m = try hint_utils.getPtrFromVarName("m", vm, ids_data, ap_tracking);
    const q = try hint_utils.getPtrFromVarName("q", vm, ids_data, ap_tracking);

    const m_range = try vm.getFeltRange(m, n_elms);
    defer m_range.deinit();
    const q_range = try vm.getFeltRange(q, n_elms * 2);
    defer q_range.deinit();

    var bytes = std.ArrayList(u8).init(allocator);
    defer bytes.deinit();

    try bytes.appendSlice(p.x.toBytesBe()[0..]);
    try bytes.appendSlice(p.y.toBytesBe()[0..]);

    for (m_range.items) |f| try bytes.appendSlice(&f.toBytesBe());
    for (q_range.items) |f| try bytes.appendSlice(&f.toBytesBe());

    const x_y = try randomEcPointSeeded(allocator, bytes.items);
    const s_addr = try hint_utils.getRelocatableFromVarName("s", vm, ids_data, ap_tracking);

    try vm.insertInMemory(allocator, s_addr, MaybeRelocatable.fromFelt(x_y[0]));
    try vm.insertInMemory(allocator, try s_addr.addUint(1), MaybeRelocatable.fromFelt(x_y[1]));
}

// Implements hint:
// from starkware.crypto.signature.signature import ALPHA, BETA, FIELD_PRIME
// from starkware.python.math_utils import recover_y
// ids.p.x = ids.x
// # This raises an exception if `x` is not on the curve.
// ids.p.y = recover_y(ids.x, ALPHA, BETA, FIELD_PRIME)
pub fn recoverYHint(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const p_x = try hint_utils.getIntegerFromVarName("x", vm, ids_data, ap_tracking);
    const p_addr = try hint_utils.getRelocatableFromVarName("p", vm, ids_data, ap_tracking);

    try vm.insertInMemory(allocator, p_addr, MaybeRelocatable.fromFelt(p_x));
    const p_y = recoverY(p_x) orelse return HintError.RecoverYPointNotOnCurve;

    try vm.insertInMemory(
        allocator,
        try p_addr.addUint(1),
        MaybeRelocatable.fromFelt(p_y),
    );
}

const ALPHA: u32 = 1;
const ALPHA_FELT: Felt252 = Felt252.fromInt(u32, ALPHA);
const BETA: u256 = 3141592653589793238462643383279502884197169399375105820974944592307816406665;
const BETA_FELT: Felt252 = Felt252.fromInt(u256, BETA);
const FELT_MAX_HALVED: u256 = 1809251394333065606848661391547535052811553607665798349986546028067936010240;

// Recovers the corresponding y coordinate on the elliptic curve
//     y^2 = x^3 + alpha * x + beta (mod field_prime)
//     of a given x coordinate.
// Returns None if x is not the x coordinate of a point in the curve
fn recoverY(x: Felt252) ?Felt252 {
    const y_squared = x.mul(&ALPHA_FELT).add(&BETA_FELT).add(&x.powToInt(3));

    return if (isQuadResidueFelt(y_squared))
        y_squared.sqrt()
    else
        null;
}

// Implementation adapted from sympy implementation
// Conditions:
// + prime is ommited as it will be CAIRO_PRIME
// + a >= 0 < prime (other cases ommited)
fn isQuadResidue(a: u512) bool {
    return a == 0 or a == 1 or field_helper.powModulus(a, FELT_MAX_HALVED, STARKNET_PRIME) == 1;
}

fn isQuadResidueFelt(a: Felt252) bool {
    return a.isZero() or a.isOne() or a.powToInt(FELT_MAX_HALVED).isOne();
}

test "EcUtils: getRandomEcPointSeeded" {
    const seed = [_]u8{
        6,   164, 190, 174, 245, 169, 52,  37,  185, 115, 23,  156, 219, 160, 201, 212, 47,  48,  224,
        26,  95,  30,  45,  183, 61,  160, 136, 75,  141, 103, 86,  252, 7,   37,  101, 236, 129, 188,
        9,   255, 83,  251, 250, 217, 147, 36,  169, 42,  165, 179, 159, 181, 130, 103, 227, 149, 232,
        171, 227, 98,  144, 235, 242, 79,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
        0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
        34,  6,   84,  253, 126, 103, 161, 35,  221, 19,  134, 128, 147, 179, 183, 119, 127, 31,  254,
        245, 150, 194, 227, 36,  242, 92,  234, 249, 20,  102, 152, 72,  44,  4,   250, 210, 105, 203,
        248, 96,  152, 14,  56,  118, 143, 233, 203, 107, 11,  154, 176, 62,  227, 254, 132, 207, 222,
        46,  204, 206, 89,  124, 135, 79,  216,
    };

    const x = Felt252.fromInt(u256, 2497468900767850684421727063357792717599762502387246235265616708902555305129);
    const y = Felt252.fromInt(u256, 3412645436898503501401619513420382337734846074629040678138428701431530606439);

    // std.log.err("x: {any}, y: {any}", .{ x.toU256(), y.toU256() });

    try std.testing.expectEqual(.{ x, y }, randomEcPointSeeded(std.testing.allocator, seed[0..]));
}

test "EcUtils: isQuadResidue less than 2" {
    try std.testing.expect(isQuadResidue(1));
    try std.testing.expect(isQuadResidue(0));
}

test "EcUtils: isQuadResidue false" {
    try std.testing.expect(!isQuadResidue(205857351767627712295703269674687767888261140702556021834663354704341414042));
}

test "EcUtils: isQuadResidue true" {
    try std.testing.expect(isQuadResidue(99957092485221722822822221624080199277265330641980989815386842231144616633668));
}

// TODO why not working figure out
// test "EcUtils: recoverY valid" {
//     const x = Felt252.fromInt(u256, 2497468900767850684421727063357792717599762502387246235265616708902555305129);
//     const y = Felt252.fromInt(u256, 205857351767627712295703269674687767888261140702556021834663354704341414042);

//     try std.testing.expectEqual(y, recoverY(x));
// }

test "EcUtils: recoverY invalid" {
    const x = Felt252.fromInt(u256, 205857351767627712295703269674687767888261140702556021834663354704341414042);

    try std.testing.expectEqual(null, recoverY(x));
}

test "EcUtils: randomEcPointHint" {
    const hint_code = hint_codes.RANDOM_EC_POINT;
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    //Initialize fp
    vm.run_context.fp = 6;
    //Create hint_data
    const ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{ .{ "p", -6 }, .{ "q", -3 }, .{ "m", -4 }, .{ "s", -1 } });

    // p.x = 3004956058830981475544150447242655232275382685012344776588097793621230049020
    // p.y = 3232266734070744637901977159303149980795588196503166389060831401046564401743
    // m = 34
    // q.x = 2864041794633455918387139831609347757720597354645583729611044800117714995244
    // q.y = 2252415379535459416893084165764951913426528160630388985542241241048300343256

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 0),
        MaybeRelocatable.fromInt(u256, 3004956058830981475544150447242655232275382685012344776588097793621230049020),
    );

    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 1),
        MaybeRelocatable.fromInt(u256, 3232266734070744637901977159303149980795588196503166389060831401046564401743),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 2),
        MaybeRelocatable.fromInt(u8, 34),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 3),
        MaybeRelocatable.fromInt(u256, 2864041794633455918387139831609347757720597354645583729611044800117714995244),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 4),
        MaybeRelocatable.fromInt(u256, 2252415379535459416893084165764951913426528160630388985542241241048300343256),
    );

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    //Execute the hint
    const hint_processor = HintProcessor{};
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // Check post-hint memory values
    // s.x = 96578541406087262240552119423829615463800550101008760434566010168435227837635
    // s.y = 3412645436898503501401619513420382337734846074629040678138428701431530606439
    try std.testing.expectEqual(Felt252.fromInt(u256, 96578541406087262240552119423829615463800550101008760434566010168435227837635), vm.getFelt(Relocatable.init(1, 5)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 3412645436898503501401619513420382337734846074629040678138428701431530606439), vm.getFelt(Relocatable.init(1, 6)));
}

test "EcUtils: chainedEcOpRandomEcPointHint" {
    const hint_code = hint_codes.CHAINED_EC_OP_RANDOM_EC_POINT;
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    //Initialize fp
    vm.run_context.fp = 6;
    //Create hint_data
    const ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{ .{ "p", -6 }, .{ "m", -4 }, .{ "q", -3 }, .{ "len", -2 }, .{ "s", -1 } });

    // p.x = 3004956058830981475544150447242655232275382685012344776588097793621230049020
    // p.y = 3232266734070744637901977159303149980795588196503166389060831401046564401743
    // m = 34
    // q.x = 2864041794633455918387139831609347757720597354645583729611044800117714995244
    // q.y = 2252415379535459416893084165764951913426528160630388985542241241048300343256
    // q = [q,q,q]
    // m = [m,m,m]
    // len = 3

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();

    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 0),
        MaybeRelocatable.fromInt(u256, 3004956058830981475544150447242655232275382685012344776588097793621230049020),
    );

    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 1),
        MaybeRelocatable.fromInt(u256, 3232266734070744637901977159303149980795588196503166389060831401046564401743),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 2),
        MaybeRelocatable.fromRelocatable(Relocatable.init(2, 0)),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 3),
        MaybeRelocatable.fromRelocatable(Relocatable.init(3, 0)),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(2, 0),
        MaybeRelocatable.fromInt(u256, 34),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(2, 1),
        MaybeRelocatable.fromInt(u256, 34),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(2, 2),
        MaybeRelocatable.fromInt(u256, 34),
    );

    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(3, 0),
        MaybeRelocatable.fromInt(u256, 2864041794633455918387139831609347757720597354645583729611044800117714995244),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(3, 1),
        MaybeRelocatable.fromInt(u256, 2252415379535459416893084165764951913426528160630388985542241241048300343256),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(3, 2),
        MaybeRelocatable.fromInt(u256, 2864041794633455918387139831609347757720597354645583729611044800117714995244),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(3, 3),
        MaybeRelocatable.fromInt(u256, 2252415379535459416893084165764951913426528160630388985542241241048300343256),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(3, 4),
        MaybeRelocatable.fromInt(u256, 2864041794633455918387139831609347757720597354645583729611044800117714995244),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(3, 5),
        MaybeRelocatable.fromInt(u256, 2252415379535459416893084165764951913426528160630388985542241241048300343256),
    );
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 4),
        MaybeRelocatable.fromInt(u256, 3),
    );

    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    //Execute the hint
    const hint_processor = HintProcessor{};
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // Check post-hint memory values
    // s.x = 1354562415074475070179359167082942891834423311678180448592849484844152837347
    // s.y = 907662328694455187848008017177970257426839229889571025406355869359245158736
    try std.testing.expectEqual(Felt252.fromInt(u256, 1354562415074475070179359167082942891834423311678180448592849484844152837347), vm.getFelt(Relocatable.init(1, 5)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 907662328694455187848008017177970257426839229889571025406355869359245158736), vm.getFelt(Relocatable.init(1, 6)));
}

test "EcUtils: recoverYHint" {
    const hint_code = hint_codes.RECOVER_Y;
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);
    //Initialize fp
    vm.run_context.fp = 3;
    //Create hint_data
    const ids_data = try testing_utils.setupIdsNonContinuousIdsData(std.testing.allocator, &.{
        .{ "x", -3 },
        .{ "p", -1 },
    });

    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    try vm.insertInMemory(
        std.testing.allocator,
        Relocatable.init(1, 0),
        MaybeRelocatable.fromInt(u256, 3004956058830981475544150447242655232275382685012344776588097793621230049020),
    );
    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    //Execute the hint
    const hint_processor = HintProcessor{};
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // Check post-hint memory values
    // s.x = 96578541406087262240552119423829615463800550101008760434566010168435227837635
    // s.y = 3412645436898503501401619513420382337734846074629040678138428701431530606439
    try std.testing.expectEqual(Felt252.fromInt(u256, 3004956058830981475544150447242655232275382685012344776588097793621230049020), vm.getFelt(Relocatable.init(1, 2)));
    try std.testing.expectEqual(Felt252.fromInt(u256, 386236054595386575795345623791920124827519018828430310912260655089307618738), vm.getFelt(Relocatable.init(1, 3)));
}
