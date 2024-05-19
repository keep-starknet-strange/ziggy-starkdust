%builtins range_check bitwise

// Code taken from https://github.com/starkware-libs/cairo-examples/blob/master/blake2s/blake2s.cairo & https://github.com/starkware-libs/cairo-examples/blob/master/blake2s/packed_blake2s.cairo
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import assert_nn_le, unsigned_div_rem
from starkware.cairo.common.memset import memset
from starkware.cairo.common.pow import pow

const BLAKE2S_INPUT_CHUNK_SIZE_FELTS = 16;
const BLAKE2S_STATE_SIZE_FELTS = 8;
// Each instance consists of 16 words of message, 8 words for the input state, 8 words
// for the output state and 2 words for t0 and f0.
const BLAKE2S_INSTANCE_SIZE = BLAKE2S_INPUT_CHUNK_SIZE_FELTS + 2 * BLAKE2S_STATE_SIZE_FELTS + 2;

const N_PACKED_INSTANCES = 7;
const ALL_ONES = 2 ** 251 - 1;
const SHIFTS = 1 + 2 ** 35 + 2 ** (35 * 2) + 2 ** (35 * 3) + 2 ** (35 * 4) + 2 ** (35 * 5) + 2 ** (
    35 * 6
);

// Computes blake2s of 'input'. Inputs of up to 64 bytes are supported.
// To use this function, split the input into (up to) 16 words of 32 bits (little endian).
// For example, to compute blake2s('Hello world'), use:
//   input = [1819043144, 1870078063, 6581362]
// where:
//   1819043144 == int.from_bytes(b'Hell', 'little')
//   1870078063 == int.from_bytes(b'o wo', 'little')
//   6581362 == int.from_bytes(b'rld', 'little')
//
// output is an array of 8 32-bit words (little endian).
//
// Assumption: n_bytes <= 64.
//
// Note: You must call finalize_blake2s() at the end of the program. Otherwise, this function
// is not sound and a malicious prover may return a wrong result.
// Note: the interface of this function may change in the future.
func blake2s{range_check_ptr, blake2s_ptr: felt*}(input: felt*, n_bytes: felt) -> (output: felt*) {
    assert_nn_le(n_bytes, 64);
    let blake2s_start = blake2s_ptr;
    _blake2s_input(input=input, n_bytes=n_bytes, n_words=BLAKE2S_INPUT_CHUNK_SIZE_FELTS);

    // Set the initial state to IV (IV[0] is modified).
    assert blake2s_ptr[0] = 0x6B08E647;  // IV[0] ^ 0x01010020 (config: no key, 32 bytes output).
    assert blake2s_ptr[1] = 0xBB67AE85;
    assert blake2s_ptr[2] = 0x3C6EF372;
    assert blake2s_ptr[3] = 0xA54FF53A;
    assert blake2s_ptr[4] = 0x510E527F;
    assert blake2s_ptr[5] = 0x9B05688C;
    assert blake2s_ptr[6] = 0x1F83D9AB;
    assert blake2s_ptr[7] = 0x5BE0CD19;
    let blake2s_ptr = blake2s_ptr + BLAKE2S_STATE_SIZE_FELTS;

    assert blake2s_ptr[0] = n_bytes;  // n_bytes.
    assert blake2s_ptr[1] = 0xffffffff;  // Is last byte = True.
    let blake2s_ptr = blake2s_ptr + 2;

    let output = blake2s_ptr;
    %{
        from starkware.cairo.common.cairo_blake2s.blake2s_utils import IV, blake2s_compress

        _blake2s_input_chunk_size_felts = int(ids.BLAKE2S_INPUT_CHUNK_SIZE_FELTS)
        assert 0 <= _blake2s_input_chunk_size_felts < 100

        new_state = blake2s_compress(
            message=memory.get_range(ids.blake2s_start, _blake2s_input_chunk_size_felts),
            h=[IV[0] ^ 0x01010020] + IV[1:],
            t0=ids.n_bytes,
            t1=0,
            f0=0xffffffff,
            f1=0,
        )

        segments.write_arg(ids.output, new_state)
    %}
    let blake2s_ptr = blake2s_ptr + BLAKE2S_STATE_SIZE_FELTS;
    return (output,);
}

func _blake2s_input{range_check_ptr, blake2s_ptr: felt*}(
    input: felt*, n_bytes: felt, n_words: felt
) {
    alloc_locals;

    local full_word;
    %{ ids.full_word = int(ids.n_bytes >= 4) %}

    if (full_word != 0) {
        assert blake2s_ptr[0] = input[0];
        let blake2s_ptr = blake2s_ptr + 1;
        return _blake2s_input(input=input + 1, n_bytes=n_bytes - 4, n_words=n_words - 1);
    }

    // This is the last input word, so we should fill the rest with zeros.

    if (n_bytes == 0) {
        memset(dst=blake2s_ptr, value=0, n=n_words);
        let blake2s_ptr = blake2s_ptr + n_words;
        return ();
    }

    assert_nn_le(n_bytes, 3);
    local range_check_ptr = range_check_ptr;

    assert blake2s_ptr[0] = input[0];

    memset(dst=blake2s_ptr + 1, value=0, n=n_words - 1);
    let blake2s_ptr = blake2s_ptr + n_words;
    return ();
}

// Verifies that the results of blake2s() are valid.
func finalize_blake2s{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    blake2s_ptr_start: felt*, blake2s_ptr_end: felt*
) {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();

    let (sigma) = _get_sigma();

    tempvar n = (blake2s_ptr_end - blake2s_ptr_start) / BLAKE2S_INSTANCE_SIZE;
    if (n == 0) {
        return ();
    }

    %{
        # Add dummy pairs of input and output.
        from starkware.cairo.common.cairo_blake2s.blake2s_utils import IV, blake2s_compress

        _n_packed_instances = int(ids.N_PACKED_INSTANCES)
        assert 0 <= _n_packed_instances < 20
        _blake2s_input_chunk_size_felts = int(ids.BLAKE2S_INPUT_CHUNK_SIZE_FELTS)
        assert 0 <= _blake2s_input_chunk_size_felts < 100

        message = [0] * _blake2s_input_chunk_size_felts
        modified_iv = [IV[0] ^ 0x01010020] + IV[1:]
        output = blake2s_compress(
            message=message,
            h=modified_iv,
            t0=0,
            t1=0,
            f0=0xffffffff,
            f1=0,
        )
        padding = (message + modified_iv + [0, 0xffffffff] + output) * (_n_packed_instances - 1)
        segments.write_arg(ids.blake2s_ptr_end, padding)
    %}

    // Compute the amount of chunks (rounded up).
    let (local n_chunks, _) = unsigned_div_rem(n + N_PACKED_INSTANCES - 1, N_PACKED_INSTANCES);
    let blake2s_ptr = blake2s_ptr_start;
    _finalize_blake2s_inner{blake2s_ptr=blake2s_ptr}(n=n_chunks, sigma=sigma);
    return ();
}

func _get_sigma() -> (sigma: felt*) {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local sigma = 0;
    local a = 1;
    local a = 2;
    local a = 3;
    local a = 4;
    local a = 5;
    local a = 6;
    local a = 7;
    local a = 8;
    local a = 9;
    local a = 10;
    local a = 11;
    local a = 12;
    local a = 13;
    local a = 14;
    local a = 15;
    local a = 14;
    local a = 10;
    local a = 4;
    local a = 8;
    local a = 9;
    local a = 15;
    local a = 13;
    local a = 6;
    local a = 1;
    local a = 12;
    local a = 0;
    local a = 2;
    local a = 11;
    local a = 7;
    local a = 5;
    local a = 3;
    local a = 11;
    local a = 8;
    local a = 12;
    local a = 0;
    local a = 5;
    local a = 2;
    local a = 15;
    local a = 13;
    local a = 10;
    local a = 14;
    local a = 3;
    local a = 6;
    local a = 7;
    local a = 1;
    local a = 9;
    local a = 4;
    local a = 7;
    local a = 9;
    local a = 3;
    local a = 1;
    local a = 13;
    local a = 12;
    local a = 11;
    local a = 14;
    local a = 2;
    local a = 6;
    local a = 5;
    local a = 10;
    local a = 4;
    local a = 0;
    local a = 15;
    local a = 8;
    local a = 9;
    local a = 0;
    local a = 5;
    local a = 7;
    local a = 2;
    local a = 4;
    local a = 10;
    local a = 15;
    local a = 14;
    local a = 1;
    local a = 11;
    local a = 12;
    local a = 6;
    local a = 8;
    local a = 3;
    local a = 13;
    local a = 2;
    local a = 12;
    local a = 6;
    local a = 10;
    local a = 0;
    local a = 11;
    local a = 8;
    local a = 3;
    local a = 4;
    local a = 13;
    local a = 7;
    local a = 5;
    local a = 15;
    local a = 14;
    local a = 1;
    local a = 9;
    local a = 12;
    local a = 5;
    local a = 1;
    local a = 15;
    local a = 14;
    local a = 13;
    local a = 4;
    local a = 10;
    local a = 0;
    local a = 7;
    local a = 6;
    local a = 3;
    local a = 9;
    local a = 2;
    local a = 8;
    local a = 11;
    local a = 13;
    local a = 11;
    local a = 7;
    local a = 14;
    local a = 12;
    local a = 1;
    local a = 3;
    local a = 9;
    local a = 5;
    local a = 0;
    local a = 15;
    local a = 4;
    local a = 8;
    local a = 6;
    local a = 2;
    local a = 10;
    local a = 6;
    local a = 15;
    local a = 14;
    local a = 9;
    local a = 11;
    local a = 3;
    local a = 0;
    local a = 8;
    local a = 12;
    local a = 2;
    local a = 13;
    local a = 7;
    local a = 1;
    local a = 4;
    local a = 10;
    local a = 5;
    local a = 10;
    local a = 2;
    local a = 8;
    local a = 4;
    local a = 7;
    local a = 6;
    local a = 1;
    local a = 5;
    local a = 15;
    local a = 11;
    local a = 9;
    local a = 14;
    local a = 3;
    local a = 12;
    local a = 13;
    local a = 0;
    return (&sigma,);
}

// Handles n chunks of N_PACKED_INSTANCES blake2s instances.
func _finalize_blake2s_inner{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, blake2s_ptr: felt*}(
    n: felt, sigma: felt*
) {
    if (n == 0) {
        return ();
    }

    alloc_locals;

    local MAX_VALUE = 2 ** 32 - 1;

    let blake2s_start = blake2s_ptr;

    // Load instance data.
    let (local data: felt*) = alloc();
    _pack_ints(BLAKE2S_INSTANCE_SIZE, data);

    let message = data;
    let input_state = message + BLAKE2S_INPUT_CHUNK_SIZE_FELTS;
    let t0_and_f0 = input_state + BLAKE2S_STATE_SIZE_FELTS;
    let output_state = t0_and_f0 + 2;

    // Run blake2s on N_PACKED_INSTANCES instances.
    local blake2s_ptr: felt* = blake2s_ptr;
    local range_check_ptr = range_check_ptr;
    blake2s_compress(
        h=input_state,
        message=data,
        t0=t0_and_f0[0],
        f0=t0_and_f0[1],
        sigma=sigma,
        output=output_state,
    );

    local bitwise_ptr: BitwiseBuiltin* = bitwise_ptr;

    let blake2s_ptr = blake2s_start + BLAKE2S_INSTANCE_SIZE * N_PACKED_INSTANCES;

    return _finalize_blake2s_inner(n=n - 1, sigma=sigma);
}

// Given N_PACKED_INSTANCES sets of m (32-bit) integers in the blake2s implicit argument,
// where each set starts at offset BLAKE2S_INSTANCE_SIZE from the previous set,
// computes m packed integers.
// blake2s_ptr is advanced m steps (just after the first set).
func _pack_ints{range_check_ptr, blake2s_ptr: felt*}(m, packed_values: felt*) {
    static_assert N_PACKED_INSTANCES == 7;
    alloc_locals;

    local MAX_VALUE = 2 ** 32 - 1;

    // TODO: consider using split_int().
    tempvar packed_values = packed_values;
    tempvar blake2s_ptr = blake2s_ptr;
    tempvar range_check_ptr = range_check_ptr;
    tempvar m = m;

    loop:
    tempvar x0 = blake2s_ptr[0 * BLAKE2S_INSTANCE_SIZE];
    assert [range_check_ptr + 0] = x0;
    assert [range_check_ptr + 1] = MAX_VALUE - x0;
    tempvar x1 = blake2s_ptr[1 * BLAKE2S_INSTANCE_SIZE];
    assert [range_check_ptr + 2] = x1;
    assert [range_check_ptr + 3] = MAX_VALUE - x1;
    tempvar x2 = blake2s_ptr[2 * BLAKE2S_INSTANCE_SIZE];
    assert [range_check_ptr + 4] = x2;
    assert [range_check_ptr + 5] = MAX_VALUE - x2;
    tempvar x3 = blake2s_ptr[3 * BLAKE2S_INSTANCE_SIZE];
    assert [range_check_ptr + 6] = x3;
    assert [range_check_ptr + 7] = MAX_VALUE - x3;
    tempvar x4 = blake2s_ptr[4 * BLAKE2S_INSTANCE_SIZE];
    assert [range_check_ptr + 8] = x4;
    assert [range_check_ptr + 9] = MAX_VALUE - x4;
    tempvar x5 = blake2s_ptr[5 * BLAKE2S_INSTANCE_SIZE];
    assert [range_check_ptr + 10] = x5;
    assert [range_check_ptr + 11] = MAX_VALUE - x5;
    tempvar x6 = blake2s_ptr[6 * BLAKE2S_INSTANCE_SIZE];
    assert [range_check_ptr + 12] = x6;
    assert [range_check_ptr + 13] = MAX_VALUE - x6;
    assert packed_values[0] = x0 + 2 ** 35 * x1 + 2 ** (35 * 2) * x2 + 2 ** (35 * 3) * x3 + 2 ** (
        35 * 4
    ) * x4 + 2 ** (35 * 5) * x5 + 2 ** (35 * 6) * x6;

    tempvar packed_values = packed_values + 1;
    tempvar blake2s_ptr = blake2s_ptr + 1;
    tempvar range_check_ptr = range_check_ptr + 14;
    tempvar m = m - 1;
    jmp loop if m != 0;

    return ();
}

func mix{bitwise_ptr: BitwiseBuiltin*}(a: felt, b: felt, c: felt, d: felt, m0: felt, m1: felt) -> (
    a: felt, b: felt, c: felt, d: felt
) {
    alloc_locals;

    // Defining the following constant as local variables saves some instructions.
    local mask32ones = SHIFTS * (2 ** 32 - 1);

    // a = (a + b + m0) % 2**32
    assert bitwise_ptr[0].x = a + b + m0;
    assert bitwise_ptr[0].y = mask32ones;
    tempvar a = bitwise_ptr[0].x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    // d = right_rot((d ^ a), 16)
    assert bitwise_ptr[0].x = a;
    assert bitwise_ptr[0].y = d;
    tempvar a_xor_d = bitwise_ptr[0].x_xor_y;
    assert bitwise_ptr[1].x = a_xor_d;
    assert bitwise_ptr[1].y = SHIFTS * (2 ** 32 - 2 ** 16);
    tempvar d = (2 ** (32 - 16)) * a_xor_d + (1 / 2 ** 16 - 2 ** (32 - 16)) * bitwise_ptr[
        1
    ].x_and_y;
    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;

    // c = (c + d) % 2**32
    assert bitwise_ptr[0].x = c + d;
    assert bitwise_ptr[0].y = mask32ones;
    tempvar c = bitwise_ptr[0].x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    // b = right_rot((b ^ c), 12)
    assert bitwise_ptr[0].x = b;
    assert bitwise_ptr[0].y = c;
    tempvar b_xor_c = bitwise_ptr[0].x_xor_y;
    assert bitwise_ptr[1].x = b_xor_c;
    assert bitwise_ptr[1].y = SHIFTS * (2 ** 32 - 2 ** 12);
    tempvar b = (2 ** (32 - 12)) * b_xor_c + (1 / 2 ** 12 - 2 ** (32 - 12)) * bitwise_ptr[
        1
    ].x_and_y;
    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;

    // a = (a + b + m1) % 2**32
    assert bitwise_ptr[0].x = a + b + m1;
    assert bitwise_ptr[0].y = mask32ones;
    tempvar a = bitwise_ptr[0].x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    // d = right_rot((d ^ a), 8)
    assert bitwise_ptr[0].x = d;
    assert bitwise_ptr[0].y = a;
    tempvar d_xor_a = bitwise_ptr[0].x_xor_y;
    assert bitwise_ptr[1].x = d_xor_a;
    assert bitwise_ptr[1].y = SHIFTS * (2 ** 32 - 2 ** 8);
    tempvar d = (2 ** (32 - 8)) * d_xor_a + (1 / 2 ** 8 - 2 ** (32 - 8)) * bitwise_ptr[1].x_and_y;
    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;

    // c = (c + d) % 2**32
    assert bitwise_ptr[0].x = c + d;
    assert bitwise_ptr[0].y = mask32ones;
    tempvar c = bitwise_ptr[0].x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    // b = right_rot((b ^ c), 7)
    assert bitwise_ptr[0].x = b;
    assert bitwise_ptr[0].y = c;
    tempvar b_xor_c = bitwise_ptr[0].x_xor_y;
    assert bitwise_ptr[1].x = b_xor_c;
    assert bitwise_ptr[1].y = SHIFTS * (2 ** 32 - 2 ** 7);
    tempvar b = (2 ** (32 - 7)) * b_xor_c + (1 / 2 ** 7 - 2 ** (32 - 7)) * bitwise_ptr[1].x_and_y;
    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;

    return (a, b, c, d);
}

func blake_round{bitwise_ptr: BitwiseBuiltin*}(state: felt*, message: felt*, sigma: felt*) -> (
    new_state: felt*
) {
    let state0 = state[0];
    let state1 = state[1];
    let state2 = state[2];
    let state3 = state[3];
    let state4 = state[4];
    let state5 = state[5];
    let state6 = state[6];
    let state7 = state[7];
    let state8 = state[8];
    let state9 = state[9];
    let state10 = state[10];
    let state11 = state[11];
    let state12 = state[12];
    let state13 = state[13];
    let state14 = state[14];
    let state15 = state[15];

    let (state0, state4, state8, state12) = mix(
        state0, state4, state8, state12, message[sigma[0]], message[sigma[1]]
    );
    let (state1, state5, state9, state13) = mix(
        state1, state5, state9, state13, message[sigma[2]], message[sigma[3]]
    );
    let (state2, state6, state10, state14) = mix(
        state2, state6, state10, state14, message[sigma[4]], message[sigma[5]]
    );
    let (state3, state7, state11, state15) = mix(
        state3, state7, state11, state15, message[sigma[6]], message[sigma[7]]
    );

    let (state0, state5, state10, state15) = mix(
        state0, state5, state10, state15, message[sigma[8]], message[sigma[9]]
    );
    let (state1, state6, state11, state12) = mix(
        state1, state6, state11, state12, message[sigma[10]], message[sigma[11]]
    );
    let (state2, state7, state8, state13) = mix(
        state2, state7, state8, state13, message[sigma[12]], message[sigma[13]]
    );
    let (state3, state4, state9, state14) = mix(
        state3, state4, state9, state14, message[sigma[14]], message[sigma[15]]
    );

    let (new_state: felt*) = alloc();
    assert new_state[0] = state0;
    assert new_state[1] = state1;
    assert new_state[2] = state2;
    assert new_state[3] = state3;
    assert new_state[4] = state4;
    assert new_state[5] = state5;
    assert new_state[6] = state6;
    assert new_state[7] = state7;
    assert new_state[8] = state8;
    assert new_state[9] = state9;
    assert new_state[10] = state10;
    assert new_state[11] = state11;
    assert new_state[12] = state12;
    assert new_state[13] = state13;
    assert new_state[14] = state14;
    assert new_state[15] = state15;

    return (new_state,);
}

// Performs the blake compression function.
//
// h is a list of 8 32-bit words.
// message is a list of 16 32-bit words.
// t1 and f1 are assumed to be 0.
func blake2s_compress{bitwise_ptr: BitwiseBuiltin*}(
    h: felt*, message: felt*, t0: felt, f0: felt, sigma: felt*, output: felt*
) {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    // Compute state[12].
    assert bitwise_ptr[0].x = 0x510e527f * SHIFTS;
    assert bitwise_ptr[0].y = t0;
    let state12 = bitwise_ptr[0].x_xor_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    // Compute state[14].
    assert bitwise_ptr[0].x = 0x1f83d9ab * SHIFTS;
    assert bitwise_ptr[0].y = f0;
    let state14 = bitwise_ptr[0].x_xor_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    local initial_state = h[0];
    local initial_state_ = h[1];
    local initial_state_ = h[2];
    local initial_state_ = h[3];
    local initial_state_ = h[4];
    local initial_state_ = h[5];
    local initial_state_ = h[6];
    local initial_state_ = h[7];
    local initial_state_ = 0x6a09e667 * SHIFTS;
    local initial_state_ = 0xbb67ae85 * SHIFTS;
    local initial_state_ = 0x3c6ef372 * SHIFTS;
    local initial_state_ = 0xa54ff53a * SHIFTS;
    local initial_state_ = state12;
    local initial_state_ = 0x9b05688c * SHIFTS;
    local initial_state_ = state14;
    local initial_state_ = 0x5be0cd19 * SHIFTS;

    let state = &initial_state;

    let (state) = blake_round(state, message, sigma + 16 * 0);
    let (state) = blake_round(state, message, sigma + 16 * 1);
    let (state) = blake_round(state, message, sigma + 16 * 2);
    let (state) = blake_round(state, message, sigma + 16 * 3);
    let (state) = blake_round(state, message, sigma + 16 * 4);
    let (state) = blake_round(state, message, sigma + 16 * 5);
    let (state) = blake_round(state, message, sigma + 16 * 6);
    let (state) = blake_round(state, message, sigma + 16 * 7);
    let (state) = blake_round(state, message, sigma + 16 * 8);
    let (state) = blake_round(state, message, sigma + 16 * 9);

    tempvar old_h = h;
    tempvar last_state = state;
    tempvar new_h = output;
    tempvar bitwise_ptr = bitwise_ptr;
    tempvar n = 8;

    loop:
    assert bitwise_ptr[0].x = old_h[0];
    assert bitwise_ptr[0].y = last_state[0];
    assert bitwise_ptr[1].x = bitwise_ptr[0].x_xor_y;
    assert bitwise_ptr[1].y = last_state[8];
    assert new_h[0] = bitwise_ptr[1].x_xor_y;

    tempvar old_h = old_h + 1;
    tempvar last_state = last_state + 1;
    tempvar new_h = new_h + 1;
    tempvar bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;
    tempvar n = n - 1;
    jmp loop if n != 0;

    return ();
}

func main{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;
    let inputs: felt* = alloc();
    assert inputs[0] = 'Hell';
    assert inputs[1] = 'o Wo';
    assert inputs[2] = 'rld';
    let (local blake2s_ptr_start) = alloc();
    let blake2s_ptr = blake2s_ptr_start;
    let (output) = blake2s{range_check_ptr=range_check_ptr, blake2s_ptr=blake2s_ptr}(inputs, 9);
    assert output[0] = 3718547061;
    assert output[1] = 125168665;
    assert output[2] = 1035352101;
    assert output[3] = 2775751047;
    assert output[4] = 2953291512;
    assert output[5] = 1978410869;
    assert output[6] = 3956807281;
    assert output[7] = 3738027290;
    finalize_blake2s(blake2s_ptr_start, blake2s_ptr);
    return ();
}
