// Core imports.
const std = @import("std");
// Local imports.
const fields = @import("fields.zig");

// Base field for the Stark curve.
// The prime is 0x800000000000011000000000000000000000000000000000000000000000001.
pub const StarkFelt252 = fields.Field(@import("stark_felt_252_gen_fp.zig"), 3618502788666131213697322783095070105623107215331596699973092056135872020481);

test "Felt252 arithmetic operations" {
    const a = StarkFelt252.one();
    const b = StarkFelt252.fromInteger(2);
    const c = a.add(b);
    try std.testing.expect(c.equal(StarkFelt252.fromInteger(3)));
}
