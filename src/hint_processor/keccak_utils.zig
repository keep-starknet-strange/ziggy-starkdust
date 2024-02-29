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

const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

const keccakF = @import("../vm/builtins/builtin_runner/keccak.zig").keccakF;

// Implements hint:
//    %{
//        from eth_hash.auto import keccak

//        data, length = ids.data, ids.length

//        if '__keccak_max_size' in globals():
//            assert length <= __keccak_max_size, \
//                f'unsafe_keccak() can only be used with length<={__keccak_max_size}. ' \
//                f'Got: length={length}.'

//        keccak_input = bytearray()
//        for word_i, byte_i in enumerate(range(0, length, 16)):
//            word = memory[data + word_i]
//            n_bytes = min(16, length - byte_i)
//            assert 0 <= word < 2 ** (8 * n_bytes)
//            keccak_input += word.to_bytes(n_bytes, 'big')

//        hashed = keccak(keccak_input)
//        ids.high = int.from_bytes(hashed[:16], 'big')
//        ids.low = int.from_bytes(hashed[16:32], 'big')
//    %}
//
pub fn unsafeKeccak(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    exec_scopes: *ExecutionScopes,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const length = try hint_utils.getIntegerFromVarName("length", vm, ids_data, ap_tracking);

    if (exec_scopes.getFelt("__keccak_max_size")) |keccak_max_size| {
        if (length.gt(keccak_max_size))
            return HintError.KeccakMaxSize;
    } else |_| {}

    // `data` is an array, represented by a pointer to the first element.
    const data = try hint_utils.getPtrFromVarName("data", vm, ids_data, ap_tracking);

    const high_addr = try hint_utils.getRelocatableFromVarName("high", vm, ids_data, ap_tracking);
    const low_addr = try hint_utils.getRelocatableFromVarName("low", vm, ids_data, ap_tracking);

    // transform to u64 to make ranges cleaner in the for loop below
    const u64_length = length.intoU64() catch return HintError.InvalidKeccakInputLength;

    const ZEROES = []u8 ** 32;

    var keccak_input = std.ArrayList(u8).init(std.testing.allocator);
    var word_i: usize = 0;
    var byte_i: u64 = 0;
    while (byte_i < u64_length) : (byte_i += 16) {
        const word_addr = Relocatable.init(data.segment_index, data.offset + word_i);

        const word = try vm.getFelt(word_addr);
        const bytes = word.toBytesBe();
        const n_bytes = @min(16, u64_length - byte_i);
        const start: usize = 32 - n_bytes;

        // word <= 2^(8 * n_bytes) <=> `start` leading zeroes
        if (!std.mem.startsWith(u8, ZEROES[0..], bytes[0..start]))
            return HintError.InvalidWordSize;

        keccak_input.appendSlice(bytes[0..start]);
        // increase step
        word_i = word_i + 1;
    }
    const hashed = try keccakF(&keccak_input.items);

    var high_bytes = []u8 ** 32;
    var low_bytes = []u8 ** 32;

    std.mem.copyForwards(u8, high_bytes[16..], hashed[0..16]);
    std.mem.copyForwards(u8, low_bytes[16..], hashed[16..32]);

    const high = Felt252.fromBytesBe(&high_bytes);
    const low = Felt252.fromBytesBe(&low_bytes);

    try vm.insertInMemory(allocator, high_addr, high);
    try vm.insertInMemory(allocator, low_addr, low);
}

test "KeccakUtils: unsafeKeccak ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    const data_ptr = try vm.addMemorySegment();

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "length",
            .elems = &.{
                MaybeRelocatable.fromFelt(Felt252.fromInt(u256, 3)),
            },
        },
        .{
            .name = "data",
            .elems = &.{
                MaybeRelocatable.fromRelocatable(data_ptr),
            },
        },
        .{
            .name = "high",
            .elems = &.{
                null,
            },
        },
        .{
            .name = "low",
            .elems = &.{
                null,
            },
        },
    }, &vm);

    defer ids_data.deinit();
    inline for (0..3) |i|
        try vm.insertInMemory(std.testing.allocator, Relocatable.init(data_ptr.segment_index, data_ptr.offset + i), MaybeRelocatable.fromFelt(Felt252.one()));

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.NONDET_N_GREATER_THAN_2, ids_data, .{});

    vm.run_context.ap.* = Relocatable.init(1, 3);
    vm.run_context.fp.* = Relocatable.init(1, 1);

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.zero(), try vm.segments.memory.getFelt(vm.run_context.getAP()));
}
