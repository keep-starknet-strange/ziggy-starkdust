const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;

/// Output built-in runner
pub const OutputBuiltinRunner = struct {
    const Self = @This();

    /// Base
    base: usize,
    /// Stop pointer
    stop_ptr: ?usize,
    /// Included boolean flag
    included: bool,

    /// Create a new OutputBuiltinRunner instance.
    ///
    /// This function initializes a new `OutputBuiltinRunner` instance with the provided `included` value.
    ///
    /// # Arguments
    ///
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `OutputBuiltinRunner` instance.
    pub fn new(included: bool) Self {
        return .{
            .base = 0,
            .stop_ptr = null,
            .included = included,
        };
    }

    pub fn deduceMemoryCell(
        self: *const Self,
        address: Relocatable,
        memory: *Memory,
    ) ?MaybeRelocatable {
        _ = memory;
        _ = address;
        _ = self;
        return null;
    }
};
