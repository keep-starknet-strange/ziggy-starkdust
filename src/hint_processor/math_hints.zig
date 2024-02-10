const std = @import("std");

const CoreVM = @import("../vm/core.zig");

const CairoVM = CoreVM.CairoVM;
const IdsManager = @import("./hint_utils.zig").IdsManager;

//Implements hint:
// %{
//     from starkware.cairo.common.math_utils import assert_integer
//     assert_integer(ids.a)
//     assert 0 <= ids.a % PRIME < range_check_builtin.bound, f'a = {ids.a} is out of range.'
// %}
fn assert_nn(ids: IdsManager, vm: *CairoVM) !void {
    const a = try ids.getFelt("a", vm);
    for (vm.builtin_runners.items) |*builtin| {
        switch (builtin.*) {
            .RangeCheck => |*range_check| {
                if (a.numBits() >= range_check.N_PARTS * range_check.INNER_RC_BOUND_SHIFT) {
                    return std.fmt.errorf("Assertion failed, 0 <= ids.a %% PRIME < range_check_builtin.bound\n a = {s} is out of range", .{a.toHexString()});
                }
            },
            else => {},
        }
    }
}
