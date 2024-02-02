const std = @import("std");
const Signature = @import("../../../math/crypto/signatures.zig").Signature;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const MemoryError = @import("../../../vm/error.zig").MemoryError;
const MathError = @import("../../../vm/error.zig").MathError;
const validation_rule = @import("../../memory/memory.zig").validation_rule;
const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const Felt252 = @import("../../../math/fields/starknet.zig").Felt252;
const ecdsa_instance_def = @import("../../types/ecdsa_instance_def.zig");

const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// inline closure for validation rule with self argument
pub inline fn SelfValidationRuleClosure(self: anytype, func: *const fn (@TypeOf(self), Allocator, *Memory, Relocatable) anyerror!std.ArrayList(Relocatable)) validation_rule {
    return (opaque {
        var hidden_self: @TypeOf(self) = undefined;
        var hidden_func: *const fn (@TypeOf(self), Allocator, *Memory, Relocatable) anyerror!std.ArrayList(Relocatable) = undefined;
        pub fn init(h_self: @TypeOf(self), h_func: *const fn (@TypeOf(self), Allocator, *Memory, Relocatable) anyerror!std.ArrayList(Relocatable)) *const @TypeOf(run) {
            hidden_self = h_self;
            hidden_func = h_func;
            return &run;
        }

        fn run(allocator: Allocator, memory: *Memory, r: Relocatable) anyerror!std.ArrayList(Relocatable) {
            return hidden_func(hidden_self, allocator, memory, r);
        }
    }).init(self, func);
}

/// Signature built-in runner
pub const SignatureBuiltinRunner = struct {
    const Self = @This();

    /// Included boolean flag
    included: bool,
    /// Ratio
    ratio: ?u32,
    /// Base
    base: usize = 0,
    /// Number of cells per instance
    cells_per_instance: u32 = 2,
    /// Number of input cells
    n_input_cells: u32 = 2,
    /// Total number of bits
    total_n_bits: u32 = 251,
    /// Stop pointer
    stop_ptr: ?usize = null,
    /// Number of instances per component
    instances_per_component: u32 = 1,
    /// Signatures HashMap
    signatures: AutoHashMap(Relocatable, Signature),

    /// Create a new SignatureBuiltinRunner instance.
    ///
    /// This function initializes a new `SignatureBuiltinRunner` instance with the provided
    /// `allocator`, `instance_def`, and `included` values.
    ///
    /// # Arguments
    ///
    /// - `allocator`: An allocator for initializing the `signatures` HashMap.
    /// - `instance_def`: A pointer to the `EcdsaInstanceDef` for this runner.
    /// - `included`: A boolean flag indicating whether this runner is included.
    ///
    /// # Returns
    ///
    /// A new `SignatureBuiltinRunner` instance.
    pub fn init(allocator: Allocator, instance_def: *ecdsa_instance_def.EcdsaInstanceDef, included: bool) Self {
        return .{
            .included = included,
            .ratio = instance_def.ratio,
            .signatures = AutoHashMap(Relocatable, Signature).init(allocator),
        };
    }

    pub fn addSignature(self: *Self, relocatable: Relocatable, rs: std.meta.Tuple(&.{ Felt252, Felt252 })) !void {
        try self.signatures.put(relocatable, .{
            .r = rs[0],
            .s = rs[1],
        });
    }

    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        self.base = @intCast((try segments.addSegment()).segment_index);
    }

    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        var result = ArrayList(MaybeRelocatable).init(allocator);
        errdefer result.deinit();

        if (self.included) {
            result.append(MaybeRelocatable.fromInt(usize, self.base));
        }

        return result;
    }

    pub fn base(self: *Self) usize {
        return self.base;
    }

    fn validationRule(self: *Self, allocator: Allocator, memory: *Memory, addr: Relocatable) anyerror!std.ArrayList(Relocatable) {
        const cell_index = @mod(addr.offset, @as(u64, @intCast(self.cells_per_instance)));
        var result = std.ArrayList(Relocatable).init(allocator);
        var pubkey_addr: Relocatable = undefined;
        var message_addr: Relocatable = undefined;

        if (cell_index == 0) {
            pubkey_addr = addr;
            message_addr = try addr.addUint(1);
        } else if (cell_index == 1) {
            if (addr.subUint(1)) |prev_addr| {
                pubkey_addr = prev_addr;
                message_addr = addr;
            } else |_| {
                return result;
            }
        } else {
            return result;
        }

        if (memory.getFelt(pubkey_addr)) |pubkey| {
            if (memory.getFelt(message)) |msg| {
                const signature = try if (self.signatures.get(pubkey_addr)) |sig| sig else MemoryError.SignatureNotFound;
            } else |_| {
                if (cell_index == 0) {
                    return result;
                }
                return MemoryError.MsgNonInt;
            }
        } else |_| {
            if (cell_index == 1) {
                return result;
            }

            return MemoryError.PubKeyNonInt;
        }
        const pubkey = try memory.getFelt();
    }

    pub fn addValidationRule(self: *Self, memory: *Memory) void {
        memory.addValidationRule(self.base, SelfValidationRuleClosure(self, &self.validationRule));
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
