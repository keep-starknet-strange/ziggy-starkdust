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

const helper = @import("../math/fields/helper.zig");
const MathError = @import("../vm/error.zig").MathError;
const HintError = @import("../vm/error.zig").HintError;
const CairoVMError = @import("../vm/error.zig").CairoVMError;

const BYTES_IN_WORD = "starkware.cairo.common.builtin_keccak.keccak.BYTES_IN_WORD";

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

    const ZEROES = [_]u8{0} ** 32;

    var keccak_input = std.ArrayList(u8).init(allocator);
    defer keccak_input.deinit();

    var word_i: usize = 0;
    var byte_i: u64 = 0;
    while (byte_i < u64_length) : (byte_i += 16) {
        const word_addr = Relocatable.init(data.segment_index, data.offset + word_i);

        const word = try vm.getFelt(word_addr);
        const bytes = word.toBytesBe();
        const n_bytes = @min(@as(usize, 16), u64_length - byte_i);
        const start: usize = @as(usize, 32) - n_bytes;

        // word <= 2^(8 * n_bytes) <=> `start` leading zeroes
        if (!std.mem.startsWith(u8, ZEROES[0..], bytes[0..start]))
            return HintError.InvalidWordSize;

        try keccak_input.appendSlice(bytes[start..]);
        // increase step
        word_i = word_i + 1;
    }

    var high_bytes = [_]u8{0} ** 32;
    var low_bytes = [_]u8{0} ** 32;

    var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
    hasher.update(keccak_input.items);

    var hashed: [32]u8 = undefined;
    hasher.final(&hashed);

    @memcpy(high_bytes[16..], hashed[0..16]);
    @memcpy(low_bytes[16..], hashed[16..32]);

    const high = Felt252.fromBytesBe(high_bytes);
    const low = Felt252.fromBytesBe(low_bytes);

    try vm.insertInMemory(allocator, high_addr, MaybeRelocatable.fromFelt(high));
    try vm.insertInMemory(allocator, low_addr, MaybeRelocatable.fromFelt(low));
}

// Implements hint:

//     %{
//         from eth_hash.auto import keccak
//         keccak_input = bytearray()
//         n_elms = ids.keccak_state.end_ptr - ids.keccak_state.start_ptr
//         for word in memory.get_range(ids.keccak_state.start_ptr, n_elms):
//             keccak_input += word.to_bytes(16, 'big')
//         hashed = keccak(keccak_input)
//         ids.high = int.from_bytes(hashed[:16], 'big')
//         ids.low = int.from_bytes(hashed[16:32], 'big')
//     %}
pub fn unsafeKeccakFinalize(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    // Just for reference (cairo code):
    // struct KeccakState:
    //     member start_ptr : felt*
    //     member end_ptr : felt*
    // end

    const keccak_state_ptr = try hint_utils.getRelocatableFromVarName("keccak_state", vm, ids_data, ap_tracking);

    // as `keccak_state` is a struct, the pointer to the struct is the same as the pointer to the first element.
    // this is why to get the pointer stored in the field `start_ptr` it is enough to pass the variable name as
    // `keccak_state`, which is the one that appears in the reference manager of the compiled JSON.
    const start_ptr = try hint_utils.getPtrFromVarName("keccak_state", vm, ids_data, ap_tracking);

    // in the KeccakState struct, the field `end_ptr` is the second one, so this variable should be get from
    // the memory cell contiguous to the one where KeccakState is pointing to.
    const end_ptr = try vm.getRelocatable(Relocatable{
        .segment_index = keccak_state_ptr.segment_index,
        .offset = keccak_state_ptr.offset + 1,
    });

    const n_elems = try end_ptr.sub(start_ptr);

    var keccak_input = std.ArrayList(u8).init(allocator);
    defer keccak_input.deinit();

    const range = try vm.getFeltRange(start_ptr, n_elems.offset);
    defer range.deinit();

    for (range.items) |word| {
        try keccak_input.appendSlice(word.toBytesBe()[16..]);
    }

    var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
    hasher.update(keccak_input.items);
    var hashed: [32]u8 = undefined;

    hasher.final(&hashed);

    var high_bytes = [_]u8{0} ** 32;
    var low_bytes = [_]u8{0} ** 32;
    @memcpy(high_bytes[16..], hashed[0..16]);
    @memcpy(low_bytes[16..], hashed[16..32]);

    const high = Felt252.fromBytesBe(high_bytes);
    const low = Felt252.fromBytesBe(low_bytes);

    const high_addr = try hint_utils.getRelocatableFromVarName("high", vm, ids_data, ap_tracking);
    const low_addr = try hint_utils.getRelocatableFromVarName("low", vm, ids_data, ap_tracking);

    try vm.insertInMemory(allocator, high_addr, MaybeRelocatable.fromFelt(high));
    try vm.insertInMemory(allocator, low_addr, MaybeRelocatable.fromFelt(low));
}

// Implements hints of type: ids.high{input_key}, ids.low{input_key} = divmod(memory[ids.inputs + {input_key}], 256 ** {exponent})
pub fn splitInput(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    input_key: usize,
    comptime exponent: u32,
) !void {
    const inputs_ptr = try hint_utils.getPtrFromVarName("inputs", vm, ids_data, ap_tracking);
    const binding = try vm.getFelt(try inputs_ptr.addUint(input_key));
    const split = Felt252.pow2Const(8 * exponent);
    const high_low = try helper.divRem(u256, binding.toInteger(), split.toInteger());
    var buffer: [20]u8 = undefined;

    try hint_utils.insertValueFromVarName(
        allocator,
        try std.fmt.bufPrint(buffer[0..], "high{d}", .{input_key}),
        MaybeRelocatable.fromInt(u256, high_low[0]),
        vm,
        ids_data,
        ap_tracking,
    );
    try hint_utils.insertValueFromVarName(
        allocator,
        try std.fmt.bufPrint(buffer[0..], "low{d}", .{input_key}),
        MaybeRelocatable.fromInt(u256, high_low[1]),
        vm,
        ids_data,
        ap_tracking,
    );
}

// Implements hints of type : ids.output{num}_low = ids.output{num} & ((1 << 128) - 1)
// ids.output{num}_high = ids.output{num} >> 128
pub fn splitOutput(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    num: u32,
) !void {
    var buffer: [30]u8 = undefined;
    const output = try hint_utils.getIntegerFromVarName(try std.fmt.bufPrint(buffer[0..], "output{d}", .{num}), vm, ids_data, ap_tracking);

    const high_low = try helper.divRem(u256, output.toInteger(), Felt252.pow2Const(128).toInteger());
    try hint_utils.insertValueFromVarName(
        allocator,
        try std.fmt.bufPrint(buffer[0..], "output{d}_high", .{num}),
        MaybeRelocatable.fromInt(u256, high_low[0]),
        vm,
        ids_data,
        ap_tracking,
    );

    try hint_utils.insertValueFromVarName(
        allocator,
        try std.fmt.bufPrint(buffer[0..], "output{}_low", .{num}),
        MaybeRelocatable.fromInt(u256, high_low[1]),
        vm,
        ids_data,
        ap_tracking,
    );
}

test "KeccakUtils: unsafeKeccak ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.addMemorySegment();
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

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("__keccak_max_size", .{
        .u64 = 500,
    });

    inline for (0..3) |i| {
        try vm.insertInMemory(std.testing.allocator, Relocatable.init(data_ptr.segment_index, data_ptr.offset + i), MaybeRelocatable.fromFelt(Felt252.one()));
    }

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.UNSAFE_KECCAK, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes);

    const high = try hint_utils.getIntegerFromVarName("high", &vm, ids_data, undefined);
    const low = try hint_utils.getIntegerFromVarName("low", &vm, ids_data, undefined);

    try std.testing.expectEqual(Felt252.fromInt(u256, 199195598804046335037364682505062700553), high);
    try std.testing.expectEqual(Felt252.fromInt(u256, 259413678945892999811634722593932702747), low);
}

test "KeccakUtils: unsafeKeccak max size exceed" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.addMemorySegment();
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

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    try exec_scopes.assignOrUpdateVariable("__keccak_max_size", .{
        .u64 = 2,
    });

    inline for (0..3) |i| {
        try vm.insertInMemory(std.testing.allocator, Relocatable.init(data_ptr.segment_index, data_ptr.offset + i), MaybeRelocatable.fromFelt(Felt252.one()));
    }

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.UNSAFE_KECCAK, ids_data, .{});

    try std.testing.expectError(HintError.KeccakMaxSize, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

test "KeccakUtils: unsafeKeccak invalid word size" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.addMemorySegment();
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

    var exec_scopes = try ExecutionScopes.init(std.testing.allocator);
    defer exec_scopes.deinit();

    inline for (0..3) |i| {
        try vm.insertInMemory(std.testing.allocator, Relocatable.init(data_ptr.segment_index, data_ptr.offset + i), MaybeRelocatable.fromFelt(Felt252.fromSignedInt(-1)));
    }

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.UNSAFE_KECCAK, ids_data, .{});

    try std.testing.expectError(HintError.InvalidWordSize, hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, &exec_scopes));
}

// Implements hint: ids.n_words_to_copy, ids.n_bytes_left = divmod(ids.n_bytes, ids.BYTES_IN_WORD)
pub fn splitNBytes(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
    constants: *const std.StringHashMap(Felt252),
) !void {
    const n_bytes =
        (try hint_utils.getIntegerFromVarName("n_bytes", vm, ids_data, ap_tracking)).intoU64() catch return HintError.Math;

    const bytes_in_word = constants.get(BYTES_IN_WORD).?.intoU64() catch return HintError.MissingConstant;

    const high_low = try helper.divModFloor(u64, n_bytes, bytes_in_word);
    try hint_utils.insertValueFromVarName(
        allocator,
        "n_words_to_copy",
        MaybeRelocatable.fromInt(u64, high_low[0]),
        vm,
        ids_data,
        ap_tracking,
    );
    try hint_utils.insertValueFromVarName(
        allocator,
        "n_bytes_left",
        MaybeRelocatable.fromInt(u64, high_low[1]),
        vm,
        ids_data,
        ap_tracking,
    );
}

// Implements hint:
// tmp, ids.output1_low = divmod(ids.output1, 256 ** 7)
// ids.output1_high, ids.output1_mid = divmod(tmp, 2 ** 128)
pub fn splitOutputMidLowHigh(
    allocator: std.mem.Allocator,
    vm: *CairoVM,
    ids_data: std.StringHashMap(HintReference),
    ap_tracking: ApTracking,
) !void {
    const output1 = try hint_utils.getIntegerFromVarName("output1", vm, ids_data, ap_tracking);
    const tmp_output1_low = try helper.divRem(u256, output1.toInteger(), Felt252.pow2Const(8 * 7).toInteger());
    const output1_high_output1_mid = try helper.divRem(u256, tmp_output1_low[0], Felt252.pow2Const(128).toInteger());

    try hint_utils.insertValueFromVarName(allocator, "output1_high", MaybeRelocatable.fromInt(u256, output1_high_output1_mid[0]), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "output1_mid", MaybeRelocatable.fromInt(u256, output1_high_output1_mid[1]), vm, ids_data, ap_tracking);
    try hint_utils.insertValueFromVarName(allocator, "output1_low", MaybeRelocatable.fromInt(u256, tmp_output1_low[1]), vm, ids_data, ap_tracking);
}

test "KeccakUtils: unsafeKeccakFinalize ok" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.addMemorySegment();
    const input_start = try vm.addMemorySegment();

    var ids_data = try testing_utils.setupIdsForTest(std.testing.allocator, &.{
        .{
            .name = "keccak_state",
            .elems = &.{
                MaybeRelocatable.fromRelocatable(input_start),
                MaybeRelocatable.fromRelocatable(try input_start.addUint(2)),
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

    try vm.insertInMemory(std.testing.allocator, input_start, MaybeRelocatable.fromFelt(Felt252.zero()));
    try vm.insertInMemory(std.testing.allocator, try input_start.addUint(1), MaybeRelocatable.fromFelt(Felt252.one()));

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.UNSAFE_KECCAK_FINALIZE, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    const high = try hint_utils.getIntegerFromVarName("high", &vm, ids_data, undefined);
    const low = try hint_utils.getIntegerFromVarName("low", &vm, ids_data, undefined);

    try std.testing.expectEqual(Felt252.fromInt(u256, 235346966651632113557018504892503714354), high);
    try std.testing.expectEqual(Felt252.fromInt(u256, 17219183504112405672555532996650339574), low);
}

test "KeccakUtils: splitInput3" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 2 }, .{ 2, 0 } },
        .{ .{ 2, 3 }, .{300} },
    });

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "high3", "low3", "inputs" });
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_INPUT_3, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // high3 hint_utils.getIntegerFromVarName("high3", &vm, ids_data, undefined)    try std.testing.expectEqual(Felt252.one(), try vm.segments.memory.getFelt(Relocatable.init(1, 0)));
    try std.testing.expectEqual(Felt252.fromInt(u8, 1), try vm.segments.memory.getFelt(Relocatable.init(1, 0)));
    try std.testing.expectEqual(Felt252.fromInt(u8, 44), try vm.segments.memory.getFelt(Relocatable.init(1, 1)));
}

test "KeccakUtils: splitInput6" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 2 }, .{ 2, 0 } },
        .{ .{ 2, 6 }, .{66036} },
    });

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "high6", "low6", "inputs" });
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_INPUT_6, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // high3 hint_utils.getIntegerFromVarName("high3", &vm, ids_data, undefined)    try std.testing.expectEqual(Felt252.one(), try vm.segments.memory.getFelt(Relocatable.init(1, 0)));
    try std.testing.expectEqual(Felt252.fromInt(u8, 1), try vm.segments.memory.getFelt(Relocatable.init(1, 0)));
    try std.testing.expectEqual(Felt252.fromInt(u16, 500), try vm.segments.memory.getFelt(Relocatable.init(1, 1)));
}

test "KeccakUtils: splitInput15" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 2 }, .{ 2, 0 } },
        .{ .{ 2, 15 }, .{15150315} },
    });

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "high15", "low15", "inputs" });
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_INPUT_15, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    // high3 hint_utils.getIntegerFromVarName("high3", &vm, ids_data, undefined)    try std.testing.expectEqual(Felt252.one(), try vm.segments.memory.getFelt(Relocatable.init(1, 0)));
    try std.testing.expectEqual(Felt252.fromInt(u8, 0), try vm.segments.memory.getFelt(Relocatable.init(1, 0)));
    try std.testing.expectEqual(Felt252.fromInt(u32, 15150315), try vm.segments.memory.getFelt(Relocatable.init(1, 1)));
}

test "KeccakUtils: splitOutput0" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{24} },
    });

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "output0", "output0_high", "output0_low" });
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_OUTPUT_0, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.fromInt(u8, 0), try vm.segments.memory.getFelt(Relocatable.init(1, 1)));
    try std.testing.expectEqual(Felt252.fromInt(u32, 24), try vm.segments.memory.getFelt(Relocatable.init(1, 2)));
}

test "KeccakUtils: splitOutput1" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{24} },
    });

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "output1", "output1_high", "output1_low" });
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_OUTPUT_1, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.fromInt(u8, 0), try vm.segments.memory.getFelt(Relocatable.init(1, 1)));
    try std.testing.expectEqual(Felt252.fromInt(u32, 24), try vm.segments.memory.getFelt(Relocatable.init(1, 2)));
}

test "KeccakUtils: splitNBytes" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 2 }, .{17} },
    });

    vm.run_context.fp = 3;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "n_words_to_copy", "n_bytes_left", "n_bytes" });
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_N_BYTES, ids_data, .{});

    var constants = std.StringHashMap(Felt252).init(std.testing.allocator);
    defer constants.deinit();

    try constants.put(BYTES_IN_WORD, Felt252.fromInt(u8, 8));

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, &constants, undefined);

    try std.testing.expectEqual(Felt252.fromInt(u8, 2), try vm.segments.memory.getFelt(Relocatable.init(1, 0)));
    try std.testing.expectEqual(Felt252.fromInt(u32, 1), try vm.segments.memory.getFelt(Relocatable.init(1, 1)));
}

test "KeccakUtils: splitOutputMidLowHigh" {
    var vm = try CairoVM.init(std.testing.allocator, .{});
    defer vm.deinit();
    defer vm.segments.memory.deinitData(std.testing.allocator);

    // _ = try vm.segments.addSegment();

    try vm.segments.memory.setUpMemory(std.testing.allocator, .{
        .{ .{ 1, 0 }, .{72057594037927938} },
    });

    vm.run_context.fp = 4;

    var ids_data = try testing_utils.setupIdsForTestWithoutMemory(std.testing.allocator, &.{ "output1", "output1_low", "output1_mid", "output1_high" });
    defer ids_data.deinit();

    const hint_processor: HintProcessor = .{};
    var hint_data = HintData.init(hint_codes.SPLIT_OUTPUT_MID_LOW_HIGH, ids_data, .{});

    try hint_processor.executeHint(std.testing.allocator, &vm, &hint_data, undefined, undefined);

    try std.testing.expectEqual(Felt252.fromInt(u8, 2), try vm.segments.memory.getFelt(Relocatable.init(1, 1)));
    try std.testing.expectEqual(Felt252.fromInt(u32, 1), try vm.segments.memory.getFelt(Relocatable.init(1, 2)));
    try std.testing.expectEqual(Felt252.fromInt(u32, 0), try vm.segments.memory.getFelt(Relocatable.init(1, 3)));
}
