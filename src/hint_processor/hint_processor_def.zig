const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const programjson = @import("../vm/types/programjson.zig");
const CairoVM = @import("../vm/core.zig").CairoVM;
const CairoVMError = @import("../vm/error.zig").CairoVMError;
const OffsetValue = programjson.OffsetValue;
const ApTracking = programjson.ApTracking;
const Reference = programjson.Reference;
const ReferenceProgram = programjson.ReferenceProgram;
const HintParams = programjson.HintParams;
const ReferenceManager = programjson.ReferenceManager;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;

/// import hint code
const hint_codes = @import("builtin_hint_codes.zig");
const math_hints = @import("math_hints.zig");

const deserialize_utils = @import("../parser/deserialize_utils.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Represents a 'compiled' hint.
///
/// This structure the return type for the `compileHint` method in the HintProcessor interface
pub const HintData = struct {
    const Self = @This();

    /// Code string that is mapped by the processor to a corresponding implementation
    code: []const u8,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,

    pub fn init(code: []const u8, ids_data: std.StringHashMap(HintReference), ap_tracking: ApTracking) Self {
        return .{
            .code = code,
            .ids_data = ids_data,
            .ap_tracking = ap_tracking,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ids_data.deinit();
    }
};

/// Represents a hint reference structure used for hints in Zig.
///
/// This structure defines a hint reference containing two offset values, a dereference flag,
/// Ap tracking data, and Cairo type information.
pub const HintReference = struct {
    const Self = @This();
    /// First offset value within the hint reference.
    offset1: OffsetValue,
    /// Second offset value within the hint reference.
    offset2: OffsetValue = .{ .value = 0 },
    /// Flag indicating dereference within the hint reference.
    dereference: bool = true,
    /// Ap tracking data associated with the hint reference (optional, defaults to null).
    ap_tracking_data: ?ApTracking = null,
    /// Cairo type information related to the hint reference (optional, defaults to null).
    cairo_type: ?[]const u8 = null,

    /// Initializes a hint reference with specified offsets and dereference flags.
    ///
    /// Params:
    ///   - `offset1`: First offset value.
    ///   - `offset2`: Second offset value.
    ///   - `inner_dereference`: Flag for inner dereference within the first offset value.
    ///   - `dereference`: Flag for dereference within the hint reference.
    pub fn init(
        offset1: i32,
        offset2: i32,
        inner_dereference: bool,
        dereference: bool,
    ) Self {
        return .{
            .offset1 = .{ .reference = .{ .FP, offset1, inner_dereference } },
            .offset2 = .{ .value = offset2 },
            .dereference = dereference,
        };
    }

    /// Initializes a simple hint reference with the specified offset.
    ///
    /// Params:
    ///   - `offset1`: First offset value for the hint reference.
    pub fn initSimple(offset1: i32) Self {
        return .{ .offset1 = .{ .reference = .{ .FP, offset1, false } } };
    }
};

/// Takes a mapping from reference name to reference id, normalizes the reference name, and maps the normalized reference name to its denoted HintReference from a reference array.
///
/// Arguments:
///   - `allocator`: The allocator that shares scope with the operating HintProcessor.
///   - `reference_ids`: A mapping from reference name to reference id
///   - `references`: An array of HintReferences, as indexed by reference id
///
/// # Returns
/// A mapping of normalized reference name to HintReference, if successful
///
/// Errors
/// - If there is no corresponding reference in `references` array
pub fn getIdsData(allocator: Allocator, reference_ids: StringHashMap(usize), references: []const HintReference) !StringHashMap(HintReference) {
    var ids_data = StringHashMap(HintReference).init(allocator);
    errdefer ids_data.deinit();

    var ref_id_it = reference_ids.iterator();
    while (ref_id_it.next()) |ref_id_entry| {
        const path = ref_id_entry.key_ptr.*;
        const ref_id = ref_id_entry.value_ptr.*;

        if (ref_id >= references.len) return CairoVMError.Unexpected;

        var name_iterator = std.mem.splitBackwardsSequence(u8, path, ".");

        const name = name_iterator.next() orelse return CairoVMError.Unexpected;
        const ref_hint = references[ref_id];

        try ids_data.put(name, ref_hint);
    }

    return ids_data;
}

pub const CairoVMHintProcessor = struct {
    const Self = @This();

    pub fn compileHint(_: *Self, allocator: Allocator, hint_params: *HintParams, references: []HintReference) !HintData {
        const ids_data = try getIdsData(allocator, hint_params.flow_tracking_data.reference_ids, references);
        errdefer ids_data.deinit();

        return .{
            .code = hint_params.code,
            // .ids = try IdsManager.init(ids_data, hint_params.flow_tracking_data.ap_tracking, hint_params.accessible_scopes),
        };
    }

    pub fn executeHint(_: *const Self, allocator: Allocator, vm: *CairoVM, hint_data: *HintData, constants: *std.StringHashMap(Felt252), exec_scopes: *ExecutionScopes) !void {
        if (std.mem.eql(u8, hint_codes.ASSERT_NN, hint_data.code)) {
            try math_hints.assertNN(vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.VERIFY_ECDSA_SIGNATURE, hint_data.code)) {
            try math_hints.verifyEcdsaSignature(vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.IS_POSITIVE, hint_data.code)) {
            try math_hints.isPositive(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.ASSERT_NOT_ZERO, hint_data.code)) {
            try math_hints.assertNonZero(vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.IS_QUAD_RESIDUE, hint_data.code)) {
            try math_hints.isQuadResidue(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SQRT, hint_data.code)) {
            try math_hints.sqrt(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UNSIGNED_DIV_REM, hint_data.code)) {
            try math_hints.unsignedDivRem(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.ASSERT_LE_FELT, hint_data.code)) {
            try math_hints.assertLeFelt(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking, constants);
        }
    }
};

test "HintReference: init should return a proper HintReference instance" {
    try expectEqual(
        HintReference{
            .offset1 = .{ .reference = .{ .FP, 10, true } },
            .offset2 = .{ .value = 22 },
            .dereference = false,
            .ap_tracking_data = null,
            .cairo_type = null,
        },
        HintReference.init(10, 22, true, false),
    );
}

test "HintReference: initSimple should return a proper HintReference instance" {
    try expectEqual(
        HintReference{
            .offset1 = .{ .reference = .{ .FP, 10, false } },
            .offset2 = .{ .value = 0 },
            .dereference = true,
            .ap_tracking_data = null,
            .cairo_type = null,
        },
        HintReference.initSimple(10),
    );
}

test "HintProcessorData: initDefault returns a proper HintProcessorData instance" {
    // Given
    const allocator = std.testing.allocator;

    // when
    var reference_ids = StringHashMap(usize).init(allocator);
    defer reference_ids.deinit();

    var references = ArrayList(HintReference).init(allocator);
    defer references.deinit();

    // Add reference data
    try reference_ids.put("starkware.cairo.common.math.split_felt.high", 0);
    try reference_ids.put("starkware.cairo.common.math.split_felt.low", 1);

    // add hint reference structs
    try references.append(HintReference.initSimple(10));
    try references.append(HintReference.initSimple(20));

    // then
    const code: []const u8 = "memory[ap] = segments.add()";

    const ids_data = try getIdsData(allocator, reference_ids, references.items);

    var hp_data = HintData.init(
        code,
        ids_data,
        .{},
    );
    defer hp_data.deinit();

    try expectEqual(@as(usize, 0), hp_data.ap_tracking.group);
    try expectEqual(@as(usize, 0), hp_data.ap_tracking.offset);
    try expectEqualStrings(code, hp_data.code);
}

test "getIdsData: should map (ref name x ref id) x (ref data) as (ref name x ref data)" {
    // Given
    const allocator = std.testing.allocator;

    // when
    var reference_ids = StringHashMap(usize).init(allocator);
    defer reference_ids.deinit();

    var references = ArrayList(HintReference).init(allocator);
    defer references.deinit();

    // Add reference data
    try reference_ids.put("starkware.cairo.common.math.split_felt.high", 0);
    try reference_ids.put("starkware.cairo.common.math.split_felt.low", 1);

    // add hint reference structs
    try references.append(HintReference.initSimple(10));
    try references.append(HintReference.initSimple(20));

    // then
    var ids_data = try getIdsData(allocator, reference_ids, references.items);
    defer ids_data.deinit();

    try expectEqual(ids_data.get("high").?.offset1.reference, .{ .FP, 10, false });
    try expectEqual(ids_data.get("low").?.offset1.reference, .{ .FP, 20, false });
}

test "getIdsData: should throw Unexpected when there is no ref data corresponding to ref ids mapping" {
    // Given
    const allocator = std.testing.allocator;

    // when
    var reference_ids = StringHashMap(usize).init(allocator);
    defer reference_ids.deinit();

    var references = ArrayList(HintReference).init(allocator);
    defer references.deinit();

    // Add reference data
    try reference_ids.put("starkware.cairo.common.math.split_felt.high", 0);
    try reference_ids.put("starkware.cairo.common.math.split_felt.low", 1);

    // add hint reference structs
    try references.append(HintReference.initSimple(10));

    // then
    try expectError(
        CairoVMError.Unexpected,
        getIdsData(allocator, reference_ids, references.items),
    );
}
