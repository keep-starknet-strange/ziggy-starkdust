const hint_utils = @import("hint_utils.zig");
const std = @import("std");
const CairoVM = @import("../vm/core.zig").CairoVM;
const HintReference = @import("hint_processor_def.zig").HintReference;
const HintProcessor = @import("hint_processor_def.zig").CairoVMHintProcessor;
const testing_utils = @import("testing_utils.zig");
const Felt252 = @import("../math/fields/starknet.zig").Felt252;
const hint_codes = @import("builtin_hint_codes.zig");
const Relocatable = @import("../vm/memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../vm/memory/relocatable.zig").MaybeRelocatable;
const ApTracking = @import("../vm/types/programjson.zig").ApTracking;
const HintData = @import("hint_processor_def.zig").HintData;
const ExecutionScopes = @import("../vm/types/execution_scopes.zig").ExecutionScopes;
const HintType = @import("../vm/types/execution_scopes.zig").HintType;

const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

// Implements hint:
//     %{
//       segments.write_arg(ids.inputs, [ids.low % 2 ** 64, ids.low // 2 ** 64])
//       segments.write_arg(ids.inputs + 2, [ids.high % 2 ** 64, ids.high // 2 ** 64])
//     %}
pub fn keccakWriteArgs(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const inputs_ptr = try hint_utils.getPtrFromVarName("inputs", vm, ids_data, ap_tracking);

    const low = try hint_utils.getIntegerFromVarName("low", vm, ids_data, ap_tracking);
    const high = try hint_utils.getIntegerFromVarName("high", vm, ids_data, ap_tracking);

    const bound = Felt252.pow2Const(64);
    const d1_d0 = try low.divRem(bound);
    const d3_d2 = try high.divRem(bound);

    var arg = std.ArrayList(Felt252).init(allocator);
    defer arg.deinit();

    try arg.appendSlice(&.{
        d1_d0.r, d1_d0.q, d3_d2.r, d3_d2.q,
    });

    try vm.segments.writeArg(std.ArrayList(Felt252), inputs_ptr, &arg);
}

// Implements hint:
//     Cairo code:
//     if nondet %{ ids.n_bytes < ids.BYTES_IN_WORD %} != 0:

//     Compiled code:
//     memory[ap] = to_felt_or_relocatable(ids.n_bytes < ids.BYTES_IN_WORD)
pub fn compareBytesInWordNondet(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const n_bytes = try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking);

    // This works fine, but it should be checked for a performance improvement.
    // One option is to try to convert n_bytes into usize, with failure to do so simply
    // making value be 0 (if it can't convert then it's either negative, which can't be in Cairo memory
    // or too big, which also means n_bytes > BYTES_IN_WORD). The other option is to exctract
    // Felt252::from(BYTES_INTO_WORD) into a lazy_static!
    const bytes_in_word = constants
        .get(hint_codes.BYTES_IN_WORD) orelse return HintError.MissingConstant;

    const value = if (n_bytes < bytes_in_word) Felt252.one() else Felt252.zero();

    try hint_utils.insertValueFromVarName(allocator, vm, value);
}

// Implements hint:
//     Cairo code:
//     if nondet %{ ids.n_bytes >= ids.KECCAK_FULL_RATE_IN_BYTES %} != 0:

//     Compiled code:
//     "memory[ap] = to_felt_or_relocatable(ids.n_bytes >= ids.KECCAK_FULL_RATE_IN_BYTES)"
pub fn compareKeccakFullRateInBytesNondet(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const n_bytes = try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking);

    const keccak_full_rate_in_bytes = constants
        .get(hint_codes.KECCAK_FULL_RATE_IN_BYTES_CAIRO_KECCAK) orelse constants.get(hint_codes.KECCAK_FULL_RATE_IN_BYTES_BUILTIN_KECCAK) orelse HintError.MissingConstant;

    const value = if (n_bytes >= keccak_full_rate_in_bytes) Felt252.one() else Felt252.zero();
    try hint_utils.insertValueIntoAp(allocator, vm, value);
}

// Implements hints:
//     %{
//         from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         assert 0 <= _keccak_state_size_felts < 100

//         output_values = keccak_func(memory.get_range(
//             ids.keccak_ptr - _keccak_state_size_felts, _keccak_state_size_felts))
//         segments.write_arg(ids.keccak_ptr, output_values)
//     %}
//     %{
//         from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         assert 0 <= _keccak_state_size_felts < 100

//         output_values = keccak_func(memory.get_range(
//             ids.keccak_ptr - _keccak_state_size_felts, _keccak_state_size_felts))
//         segments.write_arg(ids.keccak_ptr, output_values)
//     %}
pub fn blockPermutationV1(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const keccak_state_size_felts = try (constants
        .get(hint_codes.KECCAK_STATE_SIZE_FELTS) orelse HintError.MissingConstant).intoU64();

    if (keccak_state_size_felts.ge(Felt252.fromInt(i32, 100)))
        return HintError.InvalidKeccakStateSizeFelt252s;

    const keccak_ptr = try hint_utils.getPtrFromVarName("keccak_ptr", vm, ids_data, ap_tracking);

    const values = try vm.getRange(
        try keccak_ptr.sub(keccak_state_size_felts),
        keccak_state_size_felts,
    );

    const u64_values = try maybeRelocVecToU64Array(values);

    if (u64_values.items.len != 25) {
        return error.WrongMaybeRelocVec;
    }

    // this function of the keccak crate is the one used instead of keccak_func from
    // keccak_utils.py
    var hash_state: std.crypto.core.keccak.KeccakF(1600) = .{
        .st = u64_values.items,
    };

    hash_state.permuteR(24);

    const bigint_values = try u64ArrayToMayberelocatableVec(hash_state.st);

    try vm.segments.writeArg(std.ArrayList(MaybeRelocatable), keccak_ptr, &bigint_values);
}

// Implements hint:
//     %{
//         ids.full_word = int(ids.n_bytes >= 8)
//     %}
pub fn cairoKeccakIsFullWord(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const n_bytes = (try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking)).intoUsize() catch 8;

    const full_word = if (n_bytes >= 8) Felt252.one() or Felt252.zero();
    try hint_utils.insertValueFromVarName(allocator, "full_word", MaybeRelocatable.fromFelt(full_word), vm, ids_data, ap_tracking);
}

// Implements hint:
//     %{
//         from starkware.cairo.common.cairo_keccak.keccak_utils import keccak_func
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         assert 0 <= _keccak_state_size_felts < 100
//         output_values = keccak_func(memory.get_range(
//             ids.keccak_ptr_start, _keccak_state_size_felts))
//         segments.write_arg(ids.output, output_values)
//     %}
pub fn blockPermutationV2(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
) !void {
    const keccak_state_size_felts = try (constants
        .get(hint_codes.KECCAK_STATE_SIZE_FELTS) orelse HintError.MissingConstant).intoUsize();

    if (keccak_state_size_felts.ge(Felt252.fromInt(i32, 100))) {
        return HintError.InvalidKeccakStateSizeFelt252s;
    }

    const keccak_ptr = try hint_utils.getPtrFromVarName("keccak_ptr_start", vm, ids_data, ap_tracking);

    const values = try vm.getRange(keccak_ptr, keccak_state_size_felts);
    const u64_values = try maybeRelocVecToU64Array(allocator, values);

    if (u64_values.items.len != 25) {
        return error.WrongMaybeRelocVec;
    }

    // this function of the keccak crate is the one used instead of keccak_func from
    // keccak_utils.py
    var hash_state: std.crypto.core.keccak.KeccakF(1600) = .{
        .st = u64_values.items,
    };

    hash_state.permuteR(24);

    const bigint_values = try u64ArrayToMayberelocatableVec(hash_state.st);

    const output = try hint_utils.getPtrFromVarName("output", vm, ids_data, ap_tracking);
    try vm.segments.writeArg(std.ArrayList(MaybeRelocatable), output, bigint_values);
}

fn cairoKeccakFinalize(
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *std.StringHashMap(Felt252),
    block_size_limit: usize,
) !void { 
        const keccak_state_size_felts = try (constants
        .get(KECCAK_STATE_SIZE_FELTS) orelse return HintError.MissingConstant).intoUsize();
    const block_size = try (constants
        .get(BLOCK_SIZE)
        orelse return HintError.MissingConstant).intoUsize();

    if (keccak_state_size_felts>=100) return HintError.InvalidKeccakStateSizeFelt252s;

    
    if (block_size >= block_size_limit) 
     return HintError.InvalidBlockSize;


    let mut inp = vec![0; keccak_state_size_felts]
        .try_into()
        .map_err(|_| VirtualMachineError::SliceToArrayError)?;
    keccak::f1600(&mut inp);

    let mut padding = vec![Felt252::ZERO.into(); keccak_state_size_felts];
    padding.extend(u64_array_to_mayberelocatable_vec(&inp));

    let base_padding = padding.clone();

    for _ in 0..(block_size - 1) {
        padding.extend_from_slice(base_padding.as_slice());
    }

    let keccak_ptr_end = get_ptr_from_var_name("keccak_ptr_end", vm, ids_data, ap_tracking)?;

    vm.write_arg(keccak_ptr_end, &padding)
        .map_err(HintError::Memory)?;

    Ok(())
}

// /* Implements hint:
//     %{
//         # Add dummy pairs of input and output.
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         _block_size = int(ids.BLOCK_SIZE)
//         assert 0 <= _keccak_state_size_felts < 100
//         assert 0 <= _block_size < 10
//         inp = [0] * _keccak_state_size_felts
//         padding = (inp + keccak_func(inp)) * _block_size
//         segments.write_arg(ids.keccak_ptr_end, padding)
//     %}
// */
// pub(crate) fn cairo_keccak_finalize_v1(
//     vm: &mut VirtualMachine,
//     ids_data: &HashMap<String, HintReference>,
//     ap_tracking: &ApTracking,
//     constants: &HashMap<String, Felt252>,
// ) -> Result<(), HintError> {
//     cairo_keccak_finalize(vm, ids_data, ap_tracking, constants, 10)
// }

// /* Implements hint:
//     %{
//         # Add dummy pairs of input and output.
//         _keccak_state_size_felts = int(ids.KECCAK_STATE_SIZE_FELTS)
//         _block_size = int(ids.BLOCK_SIZE)
//         assert 0 <= _keccak_state_size_felts < 100
//         assert 0 <= _block_size < 1000
//         inp = [0] * _keccak_state_size_felts
//         padding = (inp + keccak_func(inp)) * _block_size
//         segments.write_arg(ids.keccak_ptr_end, padding)
//     %}
// */
// pub(crate) fn cairo_keccak_finalize_v2(
//     vm: &mut VirtualMachine,
//     ids_data: &HashMap<String, HintReference>,
//     ap_tracking: &ApTracking,
//     constants: &HashMap<String, Felt252>,
// ) -> Result<(), HintError> {
//     cairo_keccak_finalize(vm, ids_data, ap_tracking, constants, 1000)
// }

// Helper function to transform a vector of MaybeRelocatables into a vector
// of u64. Raises error if there are None's or if MaybeRelocatables are not Bigints.
pub fn maybeRelocVecToU64Array(allocator: std.mem.Allocator, vec: std.ArrayList(?MaybeRelocatable)) !std.ArrayList(u64) {
    var array = std.ArrayList(u64).init(allocator);
    errdefer array.deinit();
    for (vec.items) |n| {
        if (n != null) {
            switch (n.?) {
                .felt => |num| try array.append(num.intoU64()),
                else => {},
            }
            continue;
        }

        return CairoVMError.ExpectedIntAtRange;
    }
}

pub fn u64ArrayToMayberelocatableVec(allocator: std.mem.Allocator, array: std.ArrayList(u64)) !std.ArrayList(MaybeRelocatable) {
    var arr = std.ArrayList(MaybeRelocatable).init(allocator);

    for (array.items) |v| arr.append(MaybeRelocatable.fromInt(u64, v));
}
