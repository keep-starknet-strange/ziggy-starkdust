// code ported from starknet-crypto implementation:
// https://github.com/xJonathanLEI/starknet-rs/blob/0857bd6cd3bd34cbb06708f0a185757044171d8d/starknet-crypto/src/pedersen_hash.rs
const std = @import("std");
const curve_params = @import("../curve/curve_params.zig");
const AffinePoint = @import("../curve/ec_point.zig").AffinePoint;
const ProjectivePoint = @import("../curve/ec_point.zig").ProjectivePoint;
const Felt252 = @import("../../fields/starknet.zig").Felt252;

const CURVE_CONSTS_P0 = @import("./gen/constants.zig").CURVE_CONSTS_P0;
const CURVE_CONSTS_P1 = @import("./gen/constants.zig").CURVE_CONSTS_P1;
const CURVE_CONSTS_P2 = @import("./gen/constants.zig").CURVE_CONSTS_P2;
const CURVE_CONSTS_P3 = @import("./gen/constants.zig").CURVE_CONSTS_P3;
const CURVE_CONSTS_BITS = @import("./gen/constants.zig").CURVE_CONSTS_BITS;

const SHIFT_POINT = ProjectivePoint.from_affine_point(curve_params.SHIFT_POINT);

fn bools_to_usize_le(bits: []const bool) usize {
    var result: usize = 0;
    for (bits, 0..) |bit, ind| {
        if (bit) {
            result += @as(usize, 1) << @intCast(ind);
        }
    }

    return result;
}

fn add_points(acc: *ProjectivePoint, bits: []const bool, prep: []const AffinePoint) void {
    // Preprocessed material is lookup-tables for each chunk of bits
    const table_size = (1 << CURVE_CONSTS_BITS) - 1;

    var i: usize = 0;
    while (i < bits.len / CURVE_CONSTS_BITS) : (i += 1) {
        const offset = bools_to_usize_le(bits[i * CURVE_CONSTS_BITS .. (i + 1) * CURVE_CONSTS_BITS][0..4]);

        if (offset > 0) {
            // Table lookup at 'offset-1' in table for chunk 'i'
            acc.add_assign_affine_point(prep[i * table_size + offset - 1]);
        }
    }
}

/// Computes the Starkware version of the Pedersen hash of x and y.
///
pub fn pedersen_hash(x: Felt252, y: Felt252) Felt252 {
    const x_bits = x.toBitsLe();
    const y_bits = y.toBitsLe();

    // Compute hash
    var acc = SHIFT_POINT;

    add_points(&acc, x_bits[0..248], CURVE_CONSTS_P0[0..]); // Add a_low * P1
    add_points(&acc, x_bits[248..252], CURVE_CONSTS_P1[0..]); // Add a_high * P2
    add_points(&acc, y_bits[0..248], CURVE_CONSTS_P2[0..]); // Add b_low * P3
    add_points(&acc, y_bits[248..252], CURVE_CONSTS_P3[0..]); // Add b_high * P4

    // Convert to affine
    const result = AffinePoint.from_projective_point(&acc);

    // Return x-coordinate
    return result.x;
}

test "pedersen-hash" {
    //   Test case ported from:
    //   https://github.com/starkware-libs/crypto-cpp/blob/95864fbe11d5287e345432dbe1e80dea3c35fc58/src/starkware/crypto/ffi/crypto_lib_test.go
    const in1 = Felt252.fromInteger(
        0x03d937c035c878245caf64531a5756109c53068da139362728feb561405371cb,
    );
    const in2 = Felt252.fromInteger(
        0x0208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a,
    );
    const expected_hash = Felt252.fromInteger(
        0x030e480bed5fe53fa909cc0f8c4d99b8f9f2c016be4c41e13a4848797979c662,
    );

    const hash = pedersen_hash(in1, in2);
    try std.testing.expectEqual(hash, expected_hash);
}
