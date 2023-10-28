pub const OutputBuiltinRunner = struct {
    const Self = @This();

    base: usize,
    stop_ptr: ?usize,
    included: bool,

    pub fn new(included: bool) Self {
        return .{
            .base = 0,
            .stop_ptr = null,
            .included = included,
        };
    }

    pub fn get_base(self: *const Self) usize {
        return self.base;
    }
};
