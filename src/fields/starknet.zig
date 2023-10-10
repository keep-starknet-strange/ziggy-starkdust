// Core imports.
const std = @import("std");
// Local imports.
const fields = @import("fields.zig");

// Base field for the Stark curve.
// The prime is 0x800000000000011000000000000000000000000000000000000000000000001.
pub const Felt252 = fields.Field(@import("stark_felt_252_gen_fp.zig"), 0x800000000000011000000000000000000000000000000000000000000000001);

test "Felt252 arithmetic operations" {
    const a = Felt252.one();
    const b = Felt252.fromInteger(2);
    const c = a.add(b);
    try std.testing.expect(c.equal(Felt252.fromInteger(3)));
}
