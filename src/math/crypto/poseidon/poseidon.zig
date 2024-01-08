const std = @import("std");
const Allocator = std.mem.Allocator;
const constants = @import("constants.zig");
const Fr = @import("../../fields/stark_felt_252_gen_fp.zig");

const Felt252 = @import("../../fields/starknet.zig").Felt252;

const round_constants: [constants.roundKeys.len][3]Felt252 = val: {
    @setEvalBranchQuota(200_000);
    var result: [constants.roundKeys.len][3]Felt252 = [_][3]Felt252{[_]Felt252{Felt252.zero()} ** 3} ** constants.roundKeys.len;

    for (constants.roundKeys, 0..) |round_key, idx| {
        for (round_key, 0..) |rk, idy| {
            result[idx][idy] = Felt252.fromInteger(rk);
        }
    }

    break :val result;
};

const COMPRESSED_SIZE = (constants.FULL_ROUNDS / 2) * 3 + constants.PARTIAL_ROUNDS + 3 + (round_constants.len - (constants.FULL_ROUNDS / 2 + 1 + constants.PARTIAL_ROUNDS)) * 3;

const compress_round_constants: [COMPRESSED_SIZE]Felt252 = val: {
    @setEvalBranchQuota(200_000);
    var result: [COMPRESSED_SIZE]Felt252 = undefined;

    var append_idx = 0;

    {
        for (round_constants[0 .. constants.FULL_ROUNDS / 2]) |rk| {
            result[append_idx] = rk[0];
            result[append_idx + 1] = rk[1];
            result[append_idx + 2] = rk[2];
            append_idx += 3;
        }
    }

    {
        var idx = constants.FULL_ROUNDS / 2;

        var state = [_]Felt252{Felt252.zero()} ** 3;

        // Add keys for partial rounds
        for (0..constants.PARTIAL_ROUNDS) |_| {
            state[0] = Felt252.add(state[0], round_constants[idx][0]);
            state[1] = Felt252.add(state[1], round_constants[idx][1]);
            state[2] = Felt252.add(state[2], round_constants[idx][2]);
            // Add last state
            result[append_idx] = state[2];

            // Reset last state
            state[2] = Felt252.zero();

            const st = Felt252.add(Felt252.add(state[0], state[1]), state[2]);

            // MixLayer
            state[0] = Felt252.add(st, Felt252.mul(Felt252.two(), state[0]));
            state[1] = Felt252.sub(st, Felt252.mul(Felt252.two(), state[1]));
            state[2] = Felt252.sub(st, Felt252.mul(Felt252.two(), state[2]));

            idx += 1;
            append_idx += 1;
        }

        // Add keys for first of the last full rounds
        state[0] = Felt252.add(state[0], round_constants[idx][0]);
        state[1] = Felt252.add(state[1], round_constants[idx][1]);
        state[2] = Felt252.add(state[2], round_constants[idx][2]);

        result[append_idx] = state[0];
        result[append_idx + 1] = state[1];
        result[append_idx + 2] = state[2];

        append_idx += 3;
    }

    {
        for (round_constants[constants.FULL_ROUNDS / 2 + constants.PARTIAL_ROUNDS + 1 ..]) |rk| {
            result[append_idx] = rk[0];
            result[append_idx + 1] = rk[1];
            result[append_idx + 2] = rk[2];
            append_idx += 3;
        }
    }
    break :val result;
};

fn mix(state: *[3]Felt252) void {
    const t = Felt252.add(Felt252.add(state[0], state[1]), state[2]);

    state[0] = Felt252.add(t, Felt252.mul(Felt252.two(), state[0]));
    state[1] = Felt252.sub(t, Felt252.mul(Felt252.two(), state[1]));
    state[2] = Felt252.sub(t, Felt252.mul(Felt252.three(), state[2]));
}

/// Linear layer for MDS matrix M = ((3,1,1), (1,-1,1), (1,1,2))
/// Given state vector x, it returns Mx, optimized by precomputing t.
fn round_comp(state: *[3]Felt252, idx: usize, full: bool) void {
    if (full) {
        state[0] = Felt252.add(state[0], compress_round_constants[idx]);
        state[1] = Felt252.add(state[1], compress_round_constants[idx + 1]);
        state[2] = Felt252.add(state[2], compress_round_constants[idx + 2]);

        state[0] = Felt252.mul(Felt252.mul(state[0], state[0]), state[0]);
        state[1] = Felt252.mul(Felt252.mul(state[1], state[1]), state[1]);
        state[2] = Felt252.mul(Felt252.mul(state[2], state[2]), state[2]);
    } else {
        state[2] = Felt252.add(state[2], compress_round_constants[idx]);
        state[2] = Felt252.mul(Felt252.mul(state[2], state[2]), state[2]);
    }
    mix(state);
}

/// Poseidon permutation function.
pub fn poseidon_permute_comp(state: *[3]Felt252) void {
    var idx: usize = 0;

    // Full rounds
    for (0..(constants.FULL_ROUNDS / 2)) |_| {
        round_comp(state, idx, true);
        idx += 3;
    }

    // Partial rounds
    for (0..constants.PARTIAL_ROUNDS) |_| {
        round_comp(state, idx, false);
        idx += 1;
    }

    // Full rounds
    for (0..(constants.FULL_ROUNDS / 2)) |_| {
        round_comp(state, idx, true);
        idx += 3;
    }
}

/// Computes the Starknet Poseidon hash of x and y.
pub fn poseidon_hash(x: Felt252, y: Felt252) Felt252 {
    var state = [_]Felt252{ x, y, Felt252.two() };

    poseidon_permute_comp(&state);

    return state[0];
}

/// Computes the Starknet Poseidon hash of an arbitrary number of [Felt252]s.
///
/// Using this function is the same as using [PoseidonHasher].
pub fn poseidon_hash_many(msgs: []const Felt252) Felt252 {
    var state = [_]Felt252{Felt252.zero()} ** 3;

    var i: usize = 0;
    while (i + 1 < msgs.len) {
        state[0] = Felt252.add(state[0], msgs[i]);
        state[1] = Felt252.add(state[1], msgs[i + 1]);

        poseidon_permute_comp(&state);

        i += 2;
    }

    const rem_len = msgs.len % 2;
    if (rem_len == 1) {
        state[0] = Felt252.add(state[0], msgs[msgs.len - 1]);
    }

    state[rem_len] = Felt252.add(Felt252.one(), state[rem_len]);

    poseidon_permute_comp(&state);

    return state[0];
}

/// Computes the Starknet Poseidon hash of a single [Felt252].
pub fn poseidon_hash_single(x: Felt252) Felt252 {
    var state = [_]Felt252{
        x, Felt252.zero(), Felt252.one(),
    };

    poseidon_permute_comp(&state);

    return state[0];
}

test "poseidon-hash" {
    const test_data = [_][3]Felt252{
        .{
            Felt252.fromInteger(0xb662f9017fa7956fd70e26129b1833e10ad000fd37b4d9f4e0ce6884b7bbe),
            Felt252.fromInteger(0x1fe356bf76102cdae1bfbdc173602ead228b12904c00dad9cf16e035468bea),
            Felt252.fromInteger(0x75540825a6ecc5dc7d7c2f5f868164182742227f1367d66c43ee51ec7937a81),
        },
        .{
            Felt252.fromInteger(0xf4e01b2032298f86b539e3d3ac05ced20d2ef275273f9325f8827717156529),
            Felt252.fromInteger(0x587bc46f5f58e0511b93c31134652a689d761a9e7f234f0f130c52e4679f3a),
            Felt252.fromInteger(0xbdb3180fdcfd6d6f172beb401af54dd71b6569e6061767234db2b777adf98b),
        },
    };

    for (test_data) |input| {
        try std.testing.expectEqual(
            input[2],
            poseidon_hash(input[0], input[1]),
        );
    }
}

test "poseidon-hash-single" {
    const test_data = [_][2]Felt252{
        .{
            Felt252.fromInteger(0x9dad5d6f502ccbcb6d34ede04f0337df3b98936aaf782f4cc07d147e3a4fd6),
            Felt252.fromInteger(0x11222854783f17f1c580ff64671bc3868de034c236f956216e8ed4ab7533455),
        },
        .{
            Felt252.fromInteger(0x3164a8e2181ff7b83391b4a86bc8967f145c38f10f35fc74e9359a0c78f7b6),
            Felt252.fromInteger(0x79ad7aa7b98d47705446fa01865942119026ac748d67a5840f06948bce2306b),
        },
    };

    for (test_data) |input| {
        try std.testing.expectEqual(
            input[1],
            poseidon_hash_single(input[0]),
        );
    }
}

test "poseidon-hash-many" {
    const test_data: [2]struct {
        input: []const Felt252,
        expected: Felt252,
    } = .{
        .{
            .input = &[_]Felt252{
                Felt252.fromInteger(0x9bf52404586087391c5fbb42538692e7ca2149bac13c145ae4230a51a6fc47),
                Felt252.fromInteger(0x40304159ee9d2d611120fbd7c7fb8020cc8f7a599bfa108e0e085222b862c0),
                Felt252.fromInteger(0x46286e4f3c450761d960d6a151a9c0988f9e16f8a48d4c0a85817c009f806a),
            },
            .expected = Felt252.fromInteger(0x1ec38b38dc88bac7b0ed6ff6326f975a06a59ac601b417745fd412a5d38e4f7),
        },
        .{
            .input = &[_]Felt252{
                Felt252.fromInteger(0xbdace8883922662601b2fd197bb660b081fcf383ede60725bd080d4b5f2fd3),
                Felt252.fromInteger(0x1eb1daaf3fdad326b959dec70ced23649cdf8786537cee0c5758a1a4229097),
                Felt252.fromInteger(0x869ca04071b779d6f940cdf33e62d51521e19223ab148ef571856ff3a44ff1),
                Felt252.fromInteger(0x533e6df8d7c4b634b1f27035c8676a7439c635e1fea356484de7f0de677930),
            },
            .expected = Felt252.fromInteger(0x2520b8f910174c3e650725baacad4efafaae7623c69a0b5513d75e500f36624),
        },
    };

    for (test_data) |input| {
        try std.testing.expectEqual(
            input.expected,
            poseidon_hash_many(input.input),
        );
    }
}
