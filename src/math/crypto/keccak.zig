const std = @import("std");

const expectEqual = std.testing.expectEqual;

pub const PLEN: usize = 25;

/// Number of rounds of the Keccak-f permutation.
///
/// TODO:
/// This is only valid for `u64`
/// See [here](https://github.com/RustCrypto/sponges/blob/329d4cdcb19d77658267367e8e3ce49e2e91c64e/keccak/src/lib.rs#L133-L161) for other implementations
pub const keccakF_ROUND_COUNT: usize = 24;

const RHO = [_]u32{
    1,
    3,
    6,
    10,
    15,
    21,
    28,
    36,
    45,
    55,
    2,
    14,
    27,
    41,
    56,
    8,
    25,
    43,
    62,
    18,
    39,
    61,
    20,
    44,
};

const PI = [_]u64{
    10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
};

const RC = [_]u64{
    0x0000000000000001,
    0x0000000000008082,
    0x800000000000808a,
    0x8000000080008000,
    0x000000000000808b,
    0x0000000080000001,
    0x8000000080008081,
    0x8000000000008009,
    0x000000000000008a,
    0x0000000000000088,
    0x0000000080008009,
    0x000000008000000a,
    0x000000008000808b,
    0x800000000000008b,
    0x8000000000008089,
    0x8000000000008003,
    0x8000000000008002,
    0x8000000000000080,
    0x000000000000800a,
    0x800000008000000a,
    0x8000000080008081,
    0x8000000000008080,
    0x0000000080000001,
    0x8000000080008008,
};

/// Applies the Keccak-p sponge construction for a specific number of rounds.
///
/// This function applies the Keccak-p sponge construction on the provided `state` for the
/// specified number of `rounds`. It follows the Keccak-p permutation process as defined by
/// the round constants and transformations.
///
/// # Parameters
/// - `state`: An array representing the sponge state.
/// - `round_count`: The number of Keccak-p rounds to perform.
///
/// # Throws
/// Throws a panic if `round_count` exceeds the maximum supported round count.
pub fn keccak_p(state: *[PLEN]u64, round_count: usize) !void {
    // Check if the requested round count is supported.
    if (round_count > keccakF_ROUND_COUNT) {
        @panic("A round_count greater than keccakF_ROUND_COUNT is not supported!");
    }

    // https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.202.pdf#page=25
    // "the rounds of KECCAK-p[b, nr] match the last rounds of KECCAK-f[b]"
    // Select round constants for the specified number of rounds.
    const round_consts = RC[keccakF_ROUND_COUNT - round_count .. keccakF_ROUND_COUNT];

    for (round_consts) |*rc| {
        var array = [_]u64{0} ** 5;

        // Theta step: XOR each state column with its neighbors.
        inline for (0..5) |x| {
            inline for (0..5) |y| {
                array[x] ^= state[5 * y + x];
            }
        }

        // Theta step (continued): Calculate and apply column parity.
        inline for (0..5) |x| {
            inline for (0..5) |y| {
                state[5 * y + x] ^= array[
                    @mod(
                        x + 4,
                        5,
                    )
                ] ^ std.math.rotl(
                    u64,
                    array[
                        @mod(
                            x + 1,
                            5,
                        )
                    ],
                    1,
                );
            }
        }

        // Rho and Pi steps: Permute the state values.
        var last = state[1];
        inline for (0..24) |x| {
            array[0] = state[PI[x]];
            state[PI[x]] = std.math.rotl(u64, last, RHO[x]);
            last = array[0];
        }

        // Chi step: Apply a bitwise transformation to each state column.
        inline for (0..5) |y_step| {
            const y = 5 * y_step;

            inline for (0..5) |x| {
                array[x] = state[y + x];
            }

            inline for (0..5) |x| {
                state[y + x] = array[x] ^ (~array[
                    @mod(
                        x + 1,
                        5,
                    )
                ] & array[
                    @mod(
                        x + 2,
                        5,
                    )
                ]);
            }
        }

        // Iota step: XOR the state with a round constant.
        state[0] ^= @truncate(rc.*);
    }
}

test "keccak_p" {
    // Test vectors are copied from XKCP (eXtended Keccak Code Package)
    // https://github.com/XKCP/XKCP/blob/master/tests/TestVectors/KeccakF-1600-IntermediateValues.txt
    const state_first = [_]u64{
        0xF1258F7940E1DDE7,
        0x84D5CCF933C0478A,
        0xD598261EA65AA9EE,
        0xBD1547306F80494D,
        0x8B284E056253D057,
        0xFF97A42D7F8E6FD4,
        0x90FEE5A0A44647C4,
        0x8C5BDA0CD6192E76,
        0xAD30A6F71B19059C,
        0x30935AB7D08FFC64,
        0xEB5AA93F2317D635,
        0xA9A6E6260D712103,
        0x81A57C16DBCF555F,
        0x43B831CD0347C826,
        0x01F22F1A11A5569F,
        0x05E5635A21D9AE61,
        0x64BEFEF28CC970F2,
        0x613670957BC46611,
        0xB87C5A554FD00ECB,
        0x8C3EE88A1CCF32C8,
        0x940C7922AE3A2614,
        0x1841F924A2C509E4,
        0x16F53526E70465C2,
        0x75F644E97F30A13B,
        0xEAF1FF7B5CECA249,
    };
    const state_second = [_]u64{
        0x2D5C954DF96ECB3C,
        0x6A332CD07057B56D,
        0x093D8D1270D76B6C,
        0x8A20D9B25569D094,
        0x4F9C4F99E5E7F156,
        0xF957B9A2DA65FB38,
        0x85773DAE1275AF0D,
        0xFAF4F247C3D810F7,
        0x1F1B9EE6F79A8759,
        0xE4FECC0FEE98B425,
        0x68CE61B6B9CE68A1,
        0xDEEA66C4BA8F974F,
        0x33C43D836EAFB1F5,
        0xE00654042719DBD9,
        0x7CF8A9F009831265,
        0xFD5449A6BF174743,
        0x97DDAD33D8994B40,
        0x48EAD5FC5D0BE774,
        0xE3B8C8EE55B7B03C,
        0x91A0226E649E42E9,
        0x900E3129E7BADD7B,
        0x202A9EC5FAA3CCE8,
        0x5B3402464E1C3DB6,
        0x609F4E62A44C1059,
        0x20D06CD26A8FBF5C,
    };
    var state = [_]u64{0} ** PLEN;
    _ = try keccak_p(&state, keccakF_ROUND_COUNT);
    try expectEqual(state_first, state);
    _ = try keccak_p(&state, keccakF_ROUND_COUNT);
    try expectEqual(state_second, state);
}
