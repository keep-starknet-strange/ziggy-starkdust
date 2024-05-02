const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Relocatable = @import("./memory/relocatable.zig").Relocatable;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;

/// An entry recorded representing the state of the VM at a given point in time.
pub const TraceEntry = struct {
    pc: Relocatable,
    ap: usize,
    fp: usize,
};

/// A trace entry for every instruction that was executed.
/// Holds the register values before the instruction was executed, after going through the relocation process.
pub const RelocatedTraceEntry = struct {
    pc: usize,
    ap: usize,
    fp: usize,
};
