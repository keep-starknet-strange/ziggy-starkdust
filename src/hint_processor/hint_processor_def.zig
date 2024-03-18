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
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const RunResources = @import("../vm/runners/cairo_runner.zig").RunResources;

/// import hint code
const hint_codes = @import("builtin_hint_codes.zig");
const math_hints = @import("math_hints.zig");
const memcpy_hint_utils = @import("memcpy_hint_utils.zig");
const memset_utils = @import("memset_utils.zig");
const uint256_utils = @import("uint256_utils.zig");
const usort = @import("usort.zig");
const dict_hint_utils = @import("dict_hint_utils.zig");
const cairo_keccak_hints = @import("cairo_keccak_hints.zig");
const squash_dict_utils = @import("squash_dict_utils.zig");

const poseidon_utils = @import("poseidon_utils.zig");
const keccak_utils = @import("keccak_utils.zig");
const felt_bit_length = @import("felt_bit_length.zig");
const find_element = @import("find_element.zig");
const set = @import("set.zig");
const pow_utils = @import("pow_utils.zig");
const segments = @import("segments.zig");

const deserialize_utils = @import("../parser/deserialize_utils.zig");
const print_utils = @import("./print.zig");

const testing_utils = @import("testing_utils.zig");

const HintError = @import("../vm/error.zig").HintError;

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

    pub fn deinit(self: Self, allocator: Allocator) void {
        if (self.cairo_type) |t| allocator.free(t);
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

// A map of hints that can be used to extend the current map of hints for the vm run
// The map matches the pc at which the hints should be executed to a vec of compiled hints (Outputed by HintProcessor::CompileHint)
pub const HintExtension = std.AutoHashMap(Relocatable, std.ArrayList(HintData));

pub const CairoVMHintProcessor = struct {
    const Self = @This();

    run_resources: RunResources = .{},

    //Transforms hint data outputed by the VM into whichever format will be later used by execute_hint
    pub fn compileHint(_: *Self, allocator: Allocator, hint_code: []const u8, ap_tracking: ApTracking, reference_ids: StringHashMap(usize), references: []HintReference) !HintData {
        const ids_data = try getIdsData(allocator, reference_ids, references);
        errdefer ids_data.deinit();

        return .{
            .code = hint_code,
            .ap_tracking = ap_tracking,
            .ids_data = ids_data,
        };
    }

    // Executes the hint which's data is provided by a dynamic structure previously created by compile_hint
    // Note: if the `extensive_hints` feature is activated the method used by the vm to execute hints is `execute_hint_extensive`, which's default implementation calls this method.
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
        } else if (std.mem.eql(u8, hint_codes.ASSERT_LE_FELT_EXCLUDED_0, hint_data.code)) {
            try math_hints.assertLeFeltExcluded0(allocator, vm, exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.ASSERT_LE_FELT_EXCLUDED_1, hint_data.code)) {
            try math_hints.assertLeFeltExcluded1(allocator, vm, exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.ASSERT_LE_FELT_EXCLUDED_2, hint_data.code)) {
            try math_hints.assertLeFeltExcluded2(exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.ASSERT_LT_FELT, hint_data.code)) {
            try math_hints.assertLtFelt(vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.ASSERT_250_BITS, hint_data.code)) {
            try math_hints.assert250Bit(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_FELT, hint_data.code)) {
            try math_hints.splitFelt(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_INT_ASSERT_RANGE, hint_data.code)) {
            try math_hints.splitIntAssertRange(vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SIGNED_DIV_REM, hint_data.code)) {
            try math_hints.signedDivRem(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.ADD_SEGMENT, hint_data.code)) {
            try memcpy_hint_utils.addSegment(allocator, vm);
        } else if (std.mem.eql(u8, hint_codes.VM_ENTER_SCOPE, hint_data.code)) {
            try memcpy_hint_utils.enterScope(allocator, exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.VM_EXIT_SCOPE, hint_data.code)) {
            try memcpy_hint_utils.exitScope(exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.MEMCPY_ENTER_SCOPE, hint_data.code)) {
            try memcpy_hint_utils.memcpyEnterScope(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.NONDET_N_GREATER_THAN_10, hint_data.code)) {
            try poseidon_utils.nGreaterThan10(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.NONDET_N_GREATER_THAN_2, hint_data.code)) {
            try poseidon_utils.nGreaterThan2(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UNSAFE_KECCAK, hint_data.code)) {
            try keccak_utils.unsafeKeccak(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UNSAFE_KECCAK_FINALIZE, hint_data.code)) {
            try keccak_utils.unsafeKeccakFinalize(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_INPUT_3, hint_data.code)) {
            try keccak_utils.splitInput(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, 3, 1);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_INPUT_6, hint_data.code)) {
            try keccak_utils.splitInput(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, 6, 2);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_INPUT_9, hint_data.code)) {
            try keccak_utils.splitInput(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, 9, 3);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_INPUT_12, hint_data.code)) {
            try keccak_utils.splitInput(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, 12, 4);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_INPUT_15, hint_data.code)) {
            try keccak_utils.splitInput(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, 15, 5);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_OUTPUT_0, hint_data.code)) {
            try keccak_utils.splitOutput(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, 0);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_OUTPUT_1, hint_data.code)) {
            try keccak_utils.splitOutput(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, 1);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_N_BYTES, hint_data.code)) {
            try keccak_utils.splitNBytes(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_OUTPUT_MID_LOW_HIGH, hint_data.code)) {
            try keccak_utils.splitOutputMidLowHigh(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.GET_FELT_BIT_LENGTH, hint_data.code)) {
            try felt_bit_length.getFeltBitLength(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.FIND_ELEMENT, hint_data.code)) {
            try find_element.findElement(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SEARCH_SORTED_LOWER, hint_data.code)) {
            try find_element.searchSortedLower(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SET_ADD, hint_data.code)) {
            try set.setAdd(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.POW, hint_data.code)) {
            try pow_utils.pow(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.RELOCATE_SEGMENT, hint_data.code)) {
            try segments.relocateSegment(vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.TEMPORARY_ARRAY, hint_data.code)) {
            try segments.temporaryArray(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UINT256_ADD, hint_data.code)) {
            try uint256_utils.uint256Add(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, false);
        } else if (std.mem.eql(u8, hint_codes.UINT256_ADD_LOW, hint_data.code)) {
            try uint256_utils.uint256Add(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, true);
        } else if (std.mem.eql(u8, hint_codes.UINT128_ADD, hint_data.code)) {
            try uint256_utils.uint128Add(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UINT256_SUB, hint_data.code)) {
            try uint256_utils.uint256Sub(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SPLIT_64, hint_data.code)) {
            try uint256_utils.split64(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UINT256_SQRT, hint_data.code)) {
            try uint256_utils.uint256Sqrt(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, false);
        } else if (std.mem.eql(u8, hint_codes.UINT256_SQRT_FELT, hint_data.code)) {
            try uint256_utils.uint256Sqrt(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, true);
        } else if (std.mem.eql(u8, hint_codes.UINT256_SIGNED_NN, hint_data.code)) {
            try uint256_utils.uint256SignedNn(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UINT256_UNSIGNED_DIV_REM, hint_data.code)) {
            try uint256_utils.uint256UnsignedDivRem(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UINT256_EXPANDED_UNSIGNED_DIV_REM, hint_data.code)) {
            try uint256_utils.uint256ExpandedUnsignedDivRem(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.UINT256_MUL_DIV_MOD, hint_data.code)) {
            try uint256_utils.uint256MulDivMod(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.USORT_ENTER_SCOPE, hint_data.code)) {
            try usort.usortEnterScope(allocator, exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.USORT_BODY, hint_data.code)) {
            try usort.usortBody(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.USORT_VERIFY, hint_data.code)) {
            try usort.verifyUsort(vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.USORT_VERIFY_MULTIPLICITY_ASSERT, hint_data.code)) {
            try usort.verifyMultiplicityAssert(exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.USORT_VERIFY_MULTIPLICITY_BODY, hint_data.code)) {
            try usort.verifyMultiplicityBody(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.MEMSET_ENTER_SCOPE, hint_data.code)) {
            try memset_utils.memsetEnterScope(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.MEMCPY_ENTER_SCOPE, hint_data.code)) {
            try memset_utils.memsetEnterScope(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.MEMSET_CONTINUE_LOOP, hint_data.code)) {
            try memset_utils.memsetStepLoop(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking, "continue_loop");
        } else if (std.mem.eql(u8, hint_codes.MEMCPY_CONTINUE_COPYING, hint_data.code)) {
            try memset_utils.memsetStepLoop(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking, "continue_copying");
        } else if (std.mem.eql(u8, hint_codes.DICT_NEW, hint_data.code)) {
            try dict_hint_utils.dictInit(allocator, vm, exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.DEFAULT_DICT_NEW, hint_data.code)) {
            try dict_hint_utils.defaultDictNew(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.DICT_READ, hint_data.code)) {
            try dict_hint_utils.dictRead(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.DICT_WRITE, hint_data.code)) {
            try dict_hint_utils.dictWrite(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.DICT_UPDATE, hint_data.code)) {
            try dict_hint_utils.dictUpdate(vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.DICT_SQUASH_COPY_DICT, hint_data.code)) {
            try dict_hint_utils.dictSquashCopyDict(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.DICT_SQUASH_UPDATE_PTR, hint_data.code)) {
            try dict_hint_utils.dictSquashUpdatePtr(vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.CAIRO_KECCAK_INPUT_IS_FULL_WORD, hint_data.code)) {
            try cairo_keccak_hints.cairoKeccakIsFullWord(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.KECCAK_WRITE_ARGS, hint_data.code)) {
            try cairo_keccak_hints.keccakWriteArgs(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.COMPARE_BYTES_IN_WORD_NONDET, hint_data.code)) {
            try cairo_keccak_hints.compareBytesInWordNondet(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.COMPARE_KECCAK_FULL_RATE_IN_BYTES_NONDET, hint_data.code)) {
            try cairo_keccak_hints.compareKeccakFullRateInBytesNondet(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.BLOCK_PERMUTATION, hint_data.code)) {
            try cairo_keccak_hints.blockPermutationV1(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.BLOCK_PERMUTATION_WHITELIST_V1, hint_data.code)) {
            try cairo_keccak_hints.blockPermutationV1(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.BLOCK_PERMUTATION_WHITELIST_V2, hint_data.code)) {
            try cairo_keccak_hints.blockPermutationV2(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.CAIRO_KECCAK_FINALIZE_V1, hint_data.code)) {
            try cairo_keccak_hints.cairoKeccakFinalizeV1(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.CAIRO_KECCAK_FINALIZE_V2, hint_data.code)) {
            try cairo_keccak_hints.cairoKeccakFinalizeV2(allocator, vm, hint_data.ids_data, hint_data.ap_tracking, constants);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_FIRST_ITERATION, hint_data.code)) {
            try squash_dict_utils.squashDictInnerFirstIteration(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_SKIP_LOOP, hint_data.code)) {
            try squash_dict_utils.squashDictInnerSkipLoop(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_CHECK_ACCESS_INDEX, hint_data.code)) {
            try squash_dict_utils.squashDictInnerCheckAccessIndex(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_CONTINUE_LOOP, hint_data.code)) {
            try squash_dict_utils.squashDictInnerContinueLoop(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_LEN_ASSERT, hint_data.code)) {
            try squash_dict_utils.squashDictInnerLenAssert(exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_USED_ACCESSES_ASSERT, hint_data.code)) {
            try squash_dict_utils.squashDictInnerUsedAccessesAssert(vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_ASSERT_LEN_KEYS, hint_data.code)) {
            try squash_dict_utils.squashDictInnerAssertLenKeys(exec_scopes);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT_INNER_NEXT_KEY, hint_data.code)) {
            try squash_dict_utils.squashDictInnerNextKey(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.SQUASH_DICT, hint_data.code)) {
            try squash_dict_utils.squashDict(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.PRINT_ARR, hint_data.code)) {
            try print_utils.printArray(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.PRINT_FELT, hint_data.code)) {
            try print_utils.printFelt(allocator, vm, hint_data.ids_data, hint_data.ap_tracking);
        } else if (std.mem.eql(u8, hint_codes.PRINT_DICT, hint_data.code)) {
            try print_utils.printDict(allocator, vm, exec_scopes, hint_data.ids_data, hint_data.ap_tracking);
        } else {
            std.log.err("not implemented: {s}\n", .{hint_data.code});
            return HintError.HintNotImplemented;
        }
    }

    // Executes the hint which's data is provided by a dynamic structure previously created by compile_hint
    // Also returns a map of hints to be loaded after the current hint is executed
    // Note: This is the method used by the vm to execute hints,
    // if you chose to implement this method instead of using the default implementation, then `execute_hint` will not be used
    pub fn executeHintExtensive(self: *const Self, allocator: Allocator, vm: *CairoVM, hint_data: *HintData, constants: *std.StringHashMap(Felt252), exec_scopes: *ExecutionScopes) !HintExtension {
        try self.executeHint(allocator, vm, hint_data, constants, exec_scopes);

        return HintExtension.init(allocator);
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

test "memcpyContinueCopying valid" {
    const hint_code = "n -= 1\nids.continue_copying = 1 if n > 0 else 0";
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // initialize memory segments
    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    _ = try vm.segments.addSegment();
    // initialize fp
    vm.run_context.fp.* = Relocatable.init(1, 2);
    // initialize vm scope with variable `n`
    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("n", .{ .felt = Felt252.one() });
    // initialize ids.continue_copying
    // we create a memory gap so that there is None in (1, 0), the actual addr of continue_copying
    try vm.segments.memory.setUpMemory(std.testing.allocator, &.{
        .{ .{ 1, 2 }, .{5} },
    });

    const ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{
        "continue_copying",
    });
    var hint_data = HintData.init(hint_code, ids_data, .{});
    defer hint_data.deinit();

    const hint_processor = CairoVMHintProcessor{};
    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);
}
