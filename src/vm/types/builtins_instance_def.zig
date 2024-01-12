const std = @import("std");
const Allocator = std.mem.Allocator;

const PedersenInstanceDef = @import("./pedersen_instance_def.zig").PedersenInstanceDef;
const RangeCheckInstanceDef = @import("./range_check_instance_def.zig").RangeCheckInstanceDef;
const EcdsaInstanceDef = @import("./ecdsa_instance_def.zig").EcdsaInstanceDef;
const BitwiseInstanceDef = @import("./bitwise_instance_def.zig").BitwiseInstanceDef;
const EcOpInstanceDef = @import("./ec_op_instance_def.zig").EcOpInstanceDef;
const KeccakInstanceDef = @import("./keccak_instance_def.zig").KeccakInstanceDef;
const PoseidonInstanceDef = @import("./poseidon_instance_def.zig").PoseidonInstanceDef;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Represents the definition of builtins instances in Cairo.
///
/// This structure defines instances of various builtins available within the Cairo architecture.
pub const BuiltinsInstanceDef = struct {
    const Self = @This();

    /// Represents the availability of the 'output' builtin.
    ///
    /// If `true`, the 'output' builtin is available; otherwise, it's not present.
    output: bool,
    /// Represents the instance of the 'Pedersen' builtin.
    ///
    /// If present, contains the instance definition for the 'Pedersen' builtin; otherwise, it's `null`.
    pedersen: ?PedersenInstanceDef,
    /// Represents the instance of the 'range_check' builtin.
    ///
    /// If present, contains the instance definition for the 'range_check' builtin; otherwise, it's `null`.
    range_check: ?RangeCheckInstanceDef,
    /// Represents the instance of the 'ECDSA' builtin.
    ///
    /// If present, contains the instance definition for the 'ECDSA' builtin; otherwise, it's `null`.
    ecdsa: ?EcdsaInstanceDef,
    /// Represents the instance of the 'bitwise' builtin.
    ///
    /// If present, contains the instance definition for the 'bitwise' builtin; otherwise, it's `null`.
    bitwise: ?BitwiseInstanceDef,
    /// Represents the instance of the 'ec_op' builtin.
    ///
    /// If present, contains the instance definition for the 'ec_op' builtin; otherwise, it's `null`.
    ec_op: ?EcOpInstanceDef,
    /// Represents the instance of the 'keccak' builtin.
    ///
    /// If present, contains the instance definition for the 'keccak' builtin; otherwise, it's `null`.
    keccak: ?KeccakInstanceDef,
    /// Represents the instance of the 'Poseidon' builtin.
    ///
    /// If present, contains the instance definition for the 'Poseidon' builtin; otherwise, it's `null`.
    poseidon: ?PoseidonInstanceDef,

    /// Initializes a new `BuiltinsInstanceDef` structure for the default 'plain' layout with no enabled builtins by default.
    ///
    /// This layout requires explicit specification of builtins when executing programs using Cairo.
    pub fn plain() Self {
        return .{
            .output = false,
            .pedersen = null,
            .range_check = null,
            .ecdsa = null,
            .bitwise = null,
            .ec_op = null,
            .keccak = null,
            .poseidon = null,
        };
    }

    /// Represents the 'small' layout in Cairo.
    ///
    /// Incorporates specific builtins with predefined ratios such as Pedersen, Range Check, and ECDSA instances.
    pub fn small() Self {
        return .{
            .output = true,
            .pedersen = PedersenInstanceDef{},
            .range_check = RangeCheckInstanceDef{},
            .ecdsa = EcdsaInstanceDef{},
            .bitwise = null,
            .ec_op = null,
            .keccak = null,
            .poseidon = null,
        };
    }

    /// Initializes the 'allCairo' layout.
    ///
    /// Optimized for a Cairo verifier program verified by another Cairo verifier, suited for specific cryptographic and verification tasks.
    pub fn allCairo(allocator: Allocator) !Self {
        var state_rep_keccak = std.ArrayList(u32).init(allocator);
        try state_rep_keccak.appendNTimes(200, 8);
        return .{
            .output = true,
            .pedersen = PedersenInstanceDef.init(256, 1),
            .range_check = RangeCheckInstanceDef{},
            .ecdsa = EcdsaInstanceDef.init(2048),
            .bitwise = BitwiseInstanceDef.init(16),
            .ec_op = EcOpInstanceDef.init(1024),
            .keccak = KeccakInstanceDef.init(2048, state_rep_keccak),
            .poseidon = PoseidonInstanceDef.init(256),
        };
    }

    /// Initializes a new `BuiltinsInstanceDef` structure representing the 'dynamic' layout with configurable instances.
    pub fn dynamic() Self {
        return .{
            .output = true,
            .pedersen = PedersenInstanceDef.init(null, 4),
            .range_check = RangeCheckInstanceDef.init(null, 8),
            .ecdsa = EcdsaInstanceDef.init(null),
            .bitwise = BitwiseInstanceDef.init(null),
            .ec_op = EcOpInstanceDef.init(null),
            .keccak = null,
            .poseidon = null,
        };
    }

    /// Deinitializes the resources held by the `BuiltinsInstanceDef` structure.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the `BuiltinsInstanceDef` structure.
    ///
    /// # Details
    ///
    /// - Checks if the 'Keccak' instance is not null within the structure.
    /// - Calls the `deinit` method on the 'Keccak' instance if it exists to release associated resources.
    pub fn deinit(self: *Self) void {
        if (self.keccak != null) {
            self.keccak.?.deinit();
        }
    }
};

test "BuiltinsInstanceDef: builtins plain" {
    try expectEqual(
        BuiltinsInstanceDef{
            .output = false,
            .pedersen = null,
            .range_check = null,
            .ecdsa = null,
            .bitwise = null,
            .ec_op = null,
            .keccak = null,
            .poseidon = null,
        },
        BuiltinsInstanceDef.plain(),
    );
}

test "BuiltinsInstanceDef: builtins small" {
    try expectEqual(
        BuiltinsInstanceDef{
            .output = true,
            .pedersen = .{
                .ratio = 8,
                .repetitions = 4,
                .element_height = 256,
                .element_bits = 252,
                .n_inputs = 2,
                .hash_limit = 3618502788666131213697322783095070105623107215331596699973092056135872020481,
            },
            .range_check = .{
                .ratio = 8,
                .n_parts = 8,
            },
            .ecdsa = .{
                .ratio = 512,
                .repetitions = 1,
                .height = 256,
                .n_hash_bits = 251,
            },
            .bitwise = null,
            .ec_op = null,
            .keccak = null,
            .poseidon = null,
        },
        BuiltinsInstanceDef.small(),
    );
}

test "BuiltinsInstanceDef: builtins all Cairo" {
    var actual = try BuiltinsInstanceDef.allCairo(std.testing.allocator);
    defer actual.deinit();

    var state_rep_keccak_expected = std.ArrayList(u32).init(std.testing.allocator);
    defer state_rep_keccak_expected.deinit();
    try state_rep_keccak_expected.appendNTimes(200, 8);

    try expect(actual.output);
    try expectEqual(
        @as(
            ?PedersenInstanceDef,
            .{
                .ratio = 256,
                .repetitions = 1,
                .element_height = 256,
                .element_bits = 252,
                .n_inputs = 2,
                .hash_limit = 3618502788666131213697322783095070105623107215331596699973092056135872020481,
            },
        ),
        actual.pedersen,
    );
    try expectEqual(
        @as(
            ?RangeCheckInstanceDef,
            .{
                .ratio = 8,
                .n_parts = 8,
            },
        ),
        actual.range_check,
    );
    try expectEqual(
        @as(
            ?EcdsaInstanceDef,
            .{
                .ratio = 2048,
                .repetitions = 1,
                .height = 256,
                .n_hash_bits = 251,
            },
        ),
        actual.ecdsa,
    );
    try expectEqual(
        @as(
            ?BitwiseInstanceDef,
            .{
                .ratio = 16,
                .total_n_bits = 251,
            },
        ),
        actual.bitwise,
    );
    try expectEqual(
        @as(
            ?EcOpInstanceDef,
            .{
                .ratio = 1024,
                .scalar_height = 256,
                .scalar_bits = 252,
            },
        ),
        actual.ec_op,
    );
    try expectEqual(
        @as(?u32, 2048),
        actual.keccak.?.ratio,
    );
    try expectEqual(
        @as(u32, 16),
        actual.keccak.?.instance_per_component,
    );
    try expectEqualSlices(
        u32,
        state_rep_keccak_expected.items,
        actual.keccak.?.state_rep.items,
    );

    try expectEqual(
        @as(
            ?PoseidonInstanceDef,
            .{ .ratio = 256 },
        ),
        actual.poseidon,
    );
}

test "BuiltinsInstanceDef: builtins dynamic" {
    try expectEqual(
        BuiltinsInstanceDef{
            .output = true,
            .pedersen = .{
                .ratio = null,
                .repetitions = 4,
                .element_height = 256,
                .element_bits = 252,
                .n_inputs = 2,
                .hash_limit = 3618502788666131213697322783095070105623107215331596699973092056135872020481,
            },
            .range_check = .{
                .ratio = null,
                .n_parts = 8,
            },
            .ecdsa = .{
                .ratio = null,
                .repetitions = 1,
                .height = 256,
                .n_hash_bits = 251,
            },
            .bitwise = .{
                .ratio = null,
                .total_n_bits = 251,
            },
            .ec_op = .{
                .ratio = null,
                .scalar_height = 256,
                .scalar_bits = 252,
            },
            .keccak = null,
            .poseidon = null,
        },
        BuiltinsInstanceDef.dynamic(),
    );
}
