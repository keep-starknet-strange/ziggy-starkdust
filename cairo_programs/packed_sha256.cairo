from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.math import assert_nn_le, unsigned_div_rem
from starkware.cairo.common.memset import memset
from starkware.cairo.common.pow import pow

const BLOCK_SIZE = 7;
const ALL_ONES = 2 ** 251 - 1;
// Pack the different instances with offsets of 35 bits. This is the maximal possible offset for
// 7 32-bit words and it allows space for carry bits in integer addition operations (up to
// 8 summands).
const SHIFTS = 1 + 2 ** 35 + 2 ** (35 * 2) + 2 ** (35 * 3) + 2 ** (35 * 4) + 2 ** (35 * 5) + 2 ** (
    35 * 6
);

// Given an array of size 16, extends it to the message schedule array (of size 64) by writing
// 48 more values.
// Each element represents 7 32-bit words from 7 difference instances, starting at bits
// 0, 35, 35 * 2, ..., 35 * 6.
func compute_message_schedule{bitwise_ptr: BitwiseBuiltin*}(message: felt*) {
    alloc_locals;

    // Defining the following constants as local variables saves some instructions.
    local shift_mask3 = SHIFTS * (2 ** 32 - 2 ** 3);
    local shift_mask7 = SHIFTS * (2 ** 32 - 2 ** 7);
    local shift_mask10 = SHIFTS * (2 ** 32 - 2 ** 10);
    local shift_mask17 = SHIFTS * (2 ** 32 - 2 ** 17);
    local shift_mask18 = SHIFTS * (2 ** 32 - 2 ** 18);
    local shift_mask19 = SHIFTS * (2 ** 32 - 2 ** 19);
    local mask32ones = SHIFTS * (2 ** 32 - 1);

    // Loop variables.
    tempvar bitwise_ptr = bitwise_ptr;
    tempvar message = message + 16;
    tempvar n = 64 - 16;

    loop:
    // Compute s0 = right_rot(w[i - 15], 7) ^ right_rot(w[i - 15], 18) ^ (w[i - 15] >> 3).
    tempvar w0 = message[-15];
    assert bitwise_ptr[0].x = w0;
    assert bitwise_ptr[0].y = shift_mask7;
    let w0_rot7 = (2 ** (32 - 7)) * w0 + (1 / 2 ** 7 - 2 ** (32 - 7)) * bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = w0;
    assert bitwise_ptr[1].y = shift_mask18;
    let w0_rot18 = (2 ** (32 - 18)) * w0 + (1 / 2 ** 18 - 2 ** (32 - 18)) * bitwise_ptr[1].x_and_y;
    assert bitwise_ptr[2].x = w0;
    assert bitwise_ptr[2].y = shift_mask3;
    let w0_shift3 = (1 / 2 ** 3) * bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = w0_rot7;
    assert bitwise_ptr[3].y = w0_rot18;
    assert bitwise_ptr[4].x = bitwise_ptr[3].x_xor_y;
    assert bitwise_ptr[4].y = w0_shift3;
    let s0 = bitwise_ptr[4].x_xor_y;
    let bitwise_ptr = bitwise_ptr + 5 * BitwiseBuiltin.SIZE;

    // Compute s1 = right_rot(w[i - 2], 17) ^ right_rot(w[i - 2], 19) ^ (w[i - 2] >> 10).
    tempvar w1 = message[-2];
    assert bitwise_ptr[0].x = w1;
    assert bitwise_ptr[0].y = shift_mask17;
    let w1_rot17 = (2 ** (32 - 17)) * w1 + (1 / 2 ** 17 - 2 ** (32 - 17)) * bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = w1;
    assert bitwise_ptr[1].y = shift_mask19;
    let w1_rot19 = (2 ** (32 - 19)) * w1 + (1 / 2 ** 19 - 2 ** (32 - 19)) * bitwise_ptr[1].x_and_y;
    assert bitwise_ptr[2].x = w1;
    assert bitwise_ptr[2].y = shift_mask10;
    let w1_shift10 = (1 / 2 ** 10) * bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = w1_rot17;
    assert bitwise_ptr[3].y = w1_rot19;
    assert bitwise_ptr[4].x = bitwise_ptr[3].x_xor_y;
    assert bitwise_ptr[4].y = w1_shift10;
    let s1 = bitwise_ptr[4].x_xor_y;
    let bitwise_ptr = bitwise_ptr + 5 * BitwiseBuiltin.SIZE;

    assert bitwise_ptr[0].x = message[-16] + s0 + message[-7] + s1;
    assert bitwise_ptr[0].y = mask32ones;
    assert message[0] = bitwise_ptr[0].x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    tempvar bitwise_ptr = bitwise_ptr;
    tempvar message = message + 1;
    tempvar n = n - 1;
    jmp loop if n != 0;

    return ();
}

func sha2_compress{bitwise_ptr: BitwiseBuiltin*}(
    state: felt*, message: felt*, round_constants: felt*
) -> (new_state: felt*) {
    alloc_locals;

    // Defining the following constants as local variables saves some instructions.
    local shift_mask2 = SHIFTS * (2 ** 32 - 2 ** 2);
    local shift_mask13 = SHIFTS * (2 ** 32 - 2 ** 13);
    local shift_mask22 = SHIFTS * (2 ** 32 - 2 ** 22);
    local shift_mask6 = SHIFTS * (2 ** 32 - 2 ** 6);
    local shift_mask11 = SHIFTS * (2 ** 32 - 2 ** 11);
    local shift_mask25 = SHIFTS * (2 ** 32 - 2 ** 25);
    local mask32ones = SHIFTS * (2 ** 32 - 1);

    tempvar a = state[0];
    tempvar b = state[1];
    tempvar c = state[2];
    tempvar d = state[3];
    tempvar e = state[4];
    tempvar f = state[5];
    tempvar g = state[6];
    tempvar h = state[7];
    tempvar round_constants = round_constants;
    tempvar message = message;
    tempvar bitwise_ptr = bitwise_ptr;
    tempvar n = 64;

    loop:
    // Compute s0 = right_rot(a, 2) ^ right_rot(a, 13) ^ right_rot(a, 22).
    assert bitwise_ptr[0].x = a;
    assert bitwise_ptr[0].y = shift_mask2;
    let a_rot2 = (2 ** (32 - 2)) * a + (1 / 2 ** 2 - 2 ** (32 - 2)) * bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = a;
    assert bitwise_ptr[1].y = shift_mask13;
    let a_rot13 = (2 ** (32 - 13)) * a + (1 / 2 ** 13 - 2 ** (32 - 13)) * bitwise_ptr[1].x_and_y;
    assert bitwise_ptr[2].x = a;
    assert bitwise_ptr[2].y = shift_mask22;
    let a_rot22 = (2 ** (32 - 22)) * a + (1 / 2 ** 22 - 2 ** (32 - 22)) * bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = a_rot2;
    assert bitwise_ptr[3].y = a_rot13;
    assert bitwise_ptr[4].x = bitwise_ptr[3].x_xor_y;
    assert bitwise_ptr[4].y = a_rot22;
    let s0 = bitwise_ptr[4].x_xor_y;
    let bitwise_ptr = bitwise_ptr + 5 * BitwiseBuiltin.SIZE;

    // Compute s1 = right_rot(e, 6) ^ right_rot(e, 11) ^ right_rot(e, 25).
    assert bitwise_ptr[0].x = e;
    assert bitwise_ptr[0].y = shift_mask6;
    let e_rot6 = (2 ** (32 - 6)) * e + (1 / 2 ** 6 - 2 ** (32 - 6)) * bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = e;
    assert bitwise_ptr[1].y = shift_mask11;
    let e_rot11 = (2 ** (32 - 11)) * e + (1 / 2 ** 11 - 2 ** (32 - 11)) * bitwise_ptr[1].x_and_y;
    assert bitwise_ptr[2].x = e;
    assert bitwise_ptr[2].y = shift_mask25;
    let e_rot25 = (2 ** (32 - 25)) * e + (1 / 2 ** 25 - 2 ** (32 - 25)) * bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = e_rot6;
    assert bitwise_ptr[3].y = e_rot11;
    assert bitwise_ptr[4].x = bitwise_ptr[3].x_xor_y;
    assert bitwise_ptr[4].y = e_rot25;
    let s1 = bitwise_ptr[4].x_xor_y;
    let bitwise_ptr = bitwise_ptr + 5 * BitwiseBuiltin.SIZE;

    // Compute ch = (e & f) ^ ((~e) & g).
    assert bitwise_ptr[0].x = e;
    assert bitwise_ptr[0].y = f;
    assert bitwise_ptr[1].x = ALL_ONES - e;
    assert bitwise_ptr[1].y = g;
    let ch = bitwise_ptr[0].x_and_y + bitwise_ptr[1].x_and_y;
    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;

    // Compute maj = (a & b) ^ (a & c) ^ (b & c).
    assert bitwise_ptr[0].x = a;
    assert bitwise_ptr[0].y = b;
    assert bitwise_ptr[1].x = bitwise_ptr[0].x_xor_y;
    assert bitwise_ptr[1].y = c;
    let maj = (a + b + c - bitwise_ptr[1].x_xor_y) / 2;
    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;

    tempvar temp1 = h + s1 + ch + round_constants[0] + message[0];
    tempvar temp2 = s0 + maj;

    assert bitwise_ptr[0].x = temp1 + temp2;
    assert bitwise_ptr[0].y = mask32ones;
    let new_a = bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = d + temp1;
    assert bitwise_ptr[1].y = mask32ones;
    let new_e = bitwise_ptr[1].x_and_y;
    let bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;

    tempvar new_a = new_a;
    tempvar new_b = a;
    tempvar new_c = b;
    tempvar new_d = c;
    tempvar new_e = new_e;
    tempvar new_f = e;
    tempvar new_g = f;
    tempvar new_h = g;
    tempvar round_constants = round_constants + 1;
    tempvar message = message + 1;
    tempvar bitwise_ptr = bitwise_ptr;
    tempvar n = n - 1;
    jmp loop if n != 0;

    // Add the compression result to the original state:
    let (res) = alloc();
    assert bitwise_ptr[0].x = state[0] + new_a;
    assert bitwise_ptr[0].y = mask32ones;
    assert res[0] = bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = state[1] + new_b;
    assert bitwise_ptr[1].y = mask32ones;
    assert res[1] = bitwise_ptr[1].x_and_y;
    assert bitwise_ptr[2].x = state[2] + new_c;
    assert bitwise_ptr[2].y = mask32ones;
    assert res[2] = bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = state[3] + new_d;
    assert bitwise_ptr[3].y = mask32ones;
    assert res[3] = bitwise_ptr[3].x_and_y;
    assert bitwise_ptr[4].x = state[4] + new_e;
    assert bitwise_ptr[4].y = mask32ones;
    assert res[4] = bitwise_ptr[4].x_and_y;
    assert bitwise_ptr[5].x = state[5] + new_f;
    assert bitwise_ptr[5].y = mask32ones;
    assert res[5] = bitwise_ptr[5].x_and_y;
    assert bitwise_ptr[6].x = state[6] + new_g;
    assert bitwise_ptr[6].y = mask32ones;
    assert res[6] = bitwise_ptr[6].x_and_y;
    assert bitwise_ptr[7].x = state[7] + new_h;
    assert bitwise_ptr[7].y = mask32ones;
    assert res[7] = bitwise_ptr[7].x_and_y;
    let bitwise_ptr = bitwise_ptr + 8 * BitwiseBuiltin.SIZE;

    return (res,);
}

// Returns the 64 round constants of SHA256.
func get_round_constants() -> (round_constants: felt*) {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local round_constants = 0x428A2F98 * SHIFTS;
    local a = 0x71374491 * SHIFTS;
    local a = 0xB5C0FBCF * SHIFTS;
    local a = 0xE9B5DBA5 * SHIFTS;
    local a = 0x3956C25B * SHIFTS;
    local a = 0x59F111F1 * SHIFTS;
    local a = 0x923F82A4 * SHIFTS;
    local a = 0xAB1C5ED5 * SHIFTS;
    local a = 0xD807AA98 * SHIFTS;
    local a = 0x12835B01 * SHIFTS;
    local a = 0x243185BE * SHIFTS;
    local a = 0x550C7DC3 * SHIFTS;
    local a = 0x72BE5D74 * SHIFTS;
    local a = 0x80DEB1FE * SHIFTS;
    local a = 0x9BDC06A7 * SHIFTS;
    local a = 0xC19BF174 * SHIFTS;
    local a = 0xE49B69C1 * SHIFTS;
    local a = 0xEFBE4786 * SHIFTS;
    local a = 0x0FC19DC6 * SHIFTS;
    local a = 0x240CA1CC * SHIFTS;
    local a = 0x2DE92C6F * SHIFTS;
    local a = 0x4A7484AA * SHIFTS;
    local a = 0x5CB0A9DC * SHIFTS;
    local a = 0x76F988DA * SHIFTS;
    local a = 0x983E5152 * SHIFTS;
    local a = 0xA831C66D * SHIFTS;
    local a = 0xB00327C8 * SHIFTS;
    local a = 0xBF597FC7 * SHIFTS;
    local a = 0xC6E00BF3 * SHIFTS;
    local a = 0xD5A79147 * SHIFTS;
    local a = 0x06CA6351 * SHIFTS;
    local a = 0x14292967 * SHIFTS;
    local a = 0x27B70A85 * SHIFTS;
    local a = 0x2E1B2138 * SHIFTS;
    local a = 0x4D2C6DFC * SHIFTS;
    local a = 0x53380D13 * SHIFTS;
    local a = 0x650A7354 * SHIFTS;
    local a = 0x766A0ABB * SHIFTS;
    local a = 0x81C2C92E * SHIFTS;
    local a = 0x92722C85 * SHIFTS;
    local a = 0xA2BFE8A1 * SHIFTS;
    local a = 0xA81A664B * SHIFTS;
    local a = 0xC24B8B70 * SHIFTS;
    local a = 0xC76C51A3 * SHIFTS;
    local a = 0xD192E819 * SHIFTS;
    local a = 0xD6990624 * SHIFTS;
    local a = 0xF40E3585 * SHIFTS;
    local a = 0x106AA070 * SHIFTS;
    local a = 0x19A4C116 * SHIFTS;
    local a = 0x1E376C08 * SHIFTS;
    local a = 0x2748774C * SHIFTS;
    local a = 0x34B0BCB5 * SHIFTS;
    local a = 0x391C0CB3 * SHIFTS;
    local a = 0x4ED8AA4A * SHIFTS;
    local a = 0x5B9CCA4F * SHIFTS;
    local a = 0x682E6FF3 * SHIFTS;
    local a = 0x748F82EE * SHIFTS;
    local a = 0x78A5636F * SHIFTS;
    local a = 0x84C87814 * SHIFTS;
    local a = 0x8CC70208 * SHIFTS;
    local a = 0x90BEFFFA * SHIFTS;
    local a = 0xA4506CEB * SHIFTS;
    local a = 0xBEF9A3F7 * SHIFTS;
    local a = 0xC67178F2 * SHIFTS;
    return (&round_constants,);
}

const SHA256_INPUT_CHUNK_SIZE_FELTS = 16;
const SHA256_STATE_SIZE_FELTS = 8;
// Each instance consists of 16 words of message, 8 words for the input state and 8 words
// for the output state.
const SHA256_INSTANCE_SIZE = SHA256_INPUT_CHUNK_SIZE_FELTS + 2 * SHA256_STATE_SIZE_FELTS;

// Computes SHA256 of 'input'. Inputs of up to 55 bytes are supported.
// To use this function, split the input into (up to) 14 words of 32 bits (big endian).
// For example, to compute sha256('Hello world'), use:
//   input = [1214606444, 1864398703, 1919706112]
// where:
//   1214606444 == int.from_bytes(b'Hell', 'big')
//   1864398703 == int.from_bytes(b'o wo', 'big')
//   1919706112 == int.from_bytes(b'rld\x00', 'big')  # Note the '\x00' padding.
//
// output is an array of 8 32-bit words (big endian).
//
// Assumption: n_bytes <= 55.
//
// Note: You must call finalize_sha2() at the end of the program. Otherwise, this function
// is not sound and a malicious prover may return a wrong result.
// Note: the interface of this function may change in the future.
func sha256{range_check_ptr, sha256_ptr: felt*}(input: felt*, n_bytes: felt) -> (output: felt*) {
    assert_nn_le(n_bytes, 55);
    let sha256_start = sha256_ptr;
    _sha256_input(input=input, n_bytes=n_bytes, n_words=SHA256_INPUT_CHUNK_SIZE_FELTS - 2);
    assert sha256_ptr[0] = 0;
    assert sha256_ptr[1] = n_bytes * 8;
    let sha256_ptr = sha256_ptr + 2;

    // Set the initial state to IV.
    assert sha256_ptr[0] = 0x6A09E667;
    assert sha256_ptr[1] = 0xBB67AE85;
    assert sha256_ptr[2] = 0x3C6EF372;
    assert sha256_ptr[3] = 0xA54FF53A;
    assert sha256_ptr[4] = 0x510E527F;
    assert sha256_ptr[5] = 0x9B05688C;
    assert sha256_ptr[6] = 0x1F83D9AB;
    assert sha256_ptr[7] = 0x5BE0CD19;
    let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;

    let output = sha256_ptr;
    %{
        from starkware.cairo.common.cairo_sha256.sha256_utils import (
            IV, compute_message_schedule, sha2_compress_function)

        _sha256_input_chunk_size_felts = int(ids.SHA256_INPUT_CHUNK_SIZE_FELTS)
        assert 0 <= _sha256_input_chunk_size_felts < 100

        w = compute_message_schedule(memory.get_range(
            ids.sha256_start, _sha256_input_chunk_size_felts))
        new_state = sha2_compress_function(IV, w)
        segments.write_arg(ids.output, new_state)
    %}
    let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;
    return (output,);
}

func _sha256_input{range_check_ptr, sha256_ptr: felt*}(input: felt*, n_bytes: felt, n_words: felt) {
    alloc_locals;

    local full_word;
    %{ ids.full_word = int(ids.n_bytes >= 4) %}

    if (full_word != 0) {
        assert sha256_ptr[0] = input[0];
        let sha256_ptr = sha256_ptr + 1;
        return _sha256_input(input=input + 1, n_bytes=n_bytes - 4, n_words=n_words - 1);
    }

    // This is the last input word, so we should add a byte '0x80' at the end and fill the rest with
    // zeros.

    if (n_bytes == 0) {
        assert sha256_ptr[0] = 0x80000000;
        memset(dst=sha256_ptr + 1, value=0, n=n_words - 1);
        let sha256_ptr = sha256_ptr + n_words;
        return ();
    }

    assert_nn_le(n_bytes, 3);
    let (padding) = pow(256, 3 - n_bytes);
    local range_check_ptr = range_check_ptr;

    assert sha256_ptr[0] = input[0] + padding * 0x80;

    memset(dst=sha256_ptr + 1, value=0, n=n_words - 1);
    let sha256_ptr = sha256_ptr + n_words;
    return ();
}

// Handles n blocks of BLOCK_SIZE SHA256 instances.
func _finalize_sha256_inner{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    sha256_ptr: felt*, n: felt, round_constants: felt*
) {
    if (n == 0) {
        return ();
    }

    alloc_locals;

    local MAX_VALUE = 2 ** 32 - 1;

    let sha256_start = sha256_ptr;

    let (local message_start: felt*) = alloc();
    let (local input_state_start: felt*) = alloc();

    // Handle message.

    tempvar message = message_start;
    tempvar sha256_ptr = sha256_ptr;
    tempvar range_check_ptr = range_check_ptr;
    tempvar m = SHA256_INPUT_CHUNK_SIZE_FELTS;

    message_loop:
    tempvar x0 = sha256_ptr[0 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 0] = x0;
    assert [range_check_ptr + 1] = MAX_VALUE - x0;
    tempvar x1 = sha256_ptr[1 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 2] = x1;
    assert [range_check_ptr + 3] = MAX_VALUE - x1;
    tempvar x2 = sha256_ptr[2 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 4] = x2;
    assert [range_check_ptr + 5] = MAX_VALUE - x2;
    tempvar x3 = sha256_ptr[3 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 6] = x3;
    assert [range_check_ptr + 7] = MAX_VALUE - x3;
    tempvar x4 = sha256_ptr[4 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 8] = x4;
    assert [range_check_ptr + 9] = MAX_VALUE - x4;
    tempvar x5 = sha256_ptr[5 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 10] = x5;
    assert [range_check_ptr + 11] = MAX_VALUE - x5;
    tempvar x6 = sha256_ptr[6 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 12] = x6;
    assert [range_check_ptr + 13] = MAX_VALUE - x6;
    assert message[0] = x0 + 2 ** 35 * x1 + 2 ** (35 * 2) * x2 + 2 ** (35 * 3) * x3 + 2 ** (
        35 * 4
    ) * x4 + 2 ** (35 * 5) * x5 + 2 ** (35 * 6) * x6;

    tempvar message = message + 1;
    tempvar sha256_ptr = sha256_ptr + 1;
    tempvar range_check_ptr = range_check_ptr + 14;
    tempvar m = m - 1;
    jmp message_loop if m != 0;

    // Handle input state.

    tempvar input_state = input_state_start;
    tempvar sha256_ptr = sha256_ptr;
    tempvar range_check_ptr = range_check_ptr;
    tempvar m = SHA256_STATE_SIZE_FELTS;

    input_state_loop:
    tempvar x0 = sha256_ptr[0 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 0] = x0;
    assert [range_check_ptr + 1] = MAX_VALUE - x0;
    tempvar x1 = sha256_ptr[1 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 2] = x1;
    assert [range_check_ptr + 3] = MAX_VALUE - x1;
    tempvar x2 = sha256_ptr[2 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 4] = x2;
    assert [range_check_ptr + 5] = MAX_VALUE - x2;
    tempvar x3 = sha256_ptr[3 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 6] = x3;
    assert [range_check_ptr + 7] = MAX_VALUE - x3;
    tempvar x4 = sha256_ptr[4 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 8] = x4;
    assert [range_check_ptr + 9] = MAX_VALUE - x4;
    tempvar x5 = sha256_ptr[5 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 10] = x5;
    assert [range_check_ptr + 11] = MAX_VALUE - x5;
    tempvar x6 = sha256_ptr[6 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 12] = x6;
    assert [range_check_ptr + 13] = MAX_VALUE - x6;
    assert input_state[0] = x0 + 2 ** 35 * x1 + 2 ** (35 * 2) * x2 + 2 ** (35 * 3) * x3 + 2 ** (
        35 * 4
    ) * x4 + 2 ** (35 * 5) * x5 + 2 ** (35 * 6) * x6;

    tempvar input_state = input_state + 1;
    tempvar sha256_ptr = sha256_ptr + 1;
    tempvar range_check_ptr = range_check_ptr + 14;
    tempvar m = m - 1;
    jmp input_state_loop if m != 0;

    // Run sha256 on the 7 instances.

    local sha256_ptr: felt* = sha256_ptr;
    local range_check_ptr = range_check_ptr;
    compute_message_schedule(message_start);
    let (outputs) = sha2_compress(input_state_start, message_start, round_constants);
    local bitwise_ptr: BitwiseBuiltin* = bitwise_ptr;

    // Handle outputs.

    tempvar outputs = outputs;
    tempvar sha256_ptr = sha256_ptr;
    tempvar range_check_ptr = range_check_ptr;
    tempvar m = SHA256_STATE_SIZE_FELTS;

    output_loop:
    tempvar x0 = sha256_ptr[0 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr] = x0;
    assert [range_check_ptr + 1] = MAX_VALUE - x0;
    tempvar x1 = sha256_ptr[1 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 2] = x1;
    assert [range_check_ptr + 3] = MAX_VALUE - x1;
    tempvar x2 = sha256_ptr[2 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 4] = x2;
    assert [range_check_ptr + 5] = MAX_VALUE - x2;
    tempvar x3 = sha256_ptr[3 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 6] = x3;
    assert [range_check_ptr + 7] = MAX_VALUE - x3;
    tempvar x4 = sha256_ptr[4 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 8] = x4;
    assert [range_check_ptr + 9] = MAX_VALUE - x4;
    tempvar x5 = sha256_ptr[5 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 10] = x5;
    assert [range_check_ptr + 11] = MAX_VALUE - x5;
    tempvar x6 = sha256_ptr[6 * SHA256_INSTANCE_SIZE];
    assert [range_check_ptr + 12] = x6;
    assert [range_check_ptr + 13] = MAX_VALUE - x6;
    assert outputs[0] = x0 + 2 ** 35 * x1 + 2 ** (35 * 2) * x2 + 2 ** (35 * 3) * x3 + 2 ** (
        35 * 4
    ) * x4 + 2 ** (35 * 5) * x5 + 2 ** (35 * 6) * x6;

    tempvar outputs = outputs + 1;
    tempvar sha256_ptr = sha256_ptr + 1;
    tempvar range_check_ptr = range_check_ptr + 14;
    tempvar m = m - 1;
    jmp output_loop if m != 0;

    return _finalize_sha256_inner(
        sha256_ptr=sha256_start + SHA256_INSTANCE_SIZE * BLOCK_SIZE,
        n=n - 1,
        round_constants=round_constants,
    );
}

// Verifies that the results of sha256() are valid.
func finalize_sha256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    sha256_ptr_start: felt*, sha256_ptr_end: felt*
) {
    alloc_locals;

    let (__fp__, _) = get_fp_and_pc();

    let (round_constants) = get_round_constants();

    tempvar n = (sha256_ptr_end - sha256_ptr_start) / SHA256_INSTANCE_SIZE;
    if (n == 0) {
        return ();
    }

    %{
        # Add dummy pairs of input and output.
        from starkware.cairo.common.cairo_sha256.sha256_utils import (
            IV, compute_message_schedule, sha2_compress_function)

        _block_size = int(ids.BLOCK_SIZE)
        assert 0 <= _block_size < 20
        _sha256_input_chunk_size_felts = int(ids.SHA256_INPUT_CHUNK_SIZE_FELTS)
        assert 0 <= _sha256_input_chunk_size_felts < 100

        message = [0] * _sha256_input_chunk_size_felts
        w = compute_message_schedule(message)
        output = sha2_compress_function(IV, w)
        padding = (message + IV + output) * (_block_size - 1)
        segments.write_arg(ids.sha256_ptr_end, padding)
    %}

    // Compute the amount of blocks (rounded up).
    let (local q, r) = unsigned_div_rem(n + BLOCK_SIZE - 1, BLOCK_SIZE);
    _finalize_sha256_inner(sha256_ptr_start, n=q, round_constants=round_constants);
    return ();
}

func main() {
    return ();
}
