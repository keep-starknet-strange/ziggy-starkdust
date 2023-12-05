const std = @import("std");
const Allocator = std.mem.Allocator;

const BuiltinsInstanceDef = @import("./builtins_instance_def.zig").BuiltinsInstanceDef;
const DilutedPoolInstanceDef = @import("./diluted_pool_instance_def.zig").DilutedPoolInstanceDef;
const CpuInstanceDef = @import("./cpu_instance_def.zig").CpuInstanceDef;

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

/// Represents the layout configuration for Cairo programs.
pub const CairoLayout = struct {
    const Self = @This();

    /// The name of the layout.
    name: []const u8,
    /// The step count in the CPU component.
    cpu_component_step: u32,
    /// The number of Range Check units.
    rc_units: u32,
    /// The built-in instances configuration.
    builtins: BuiltinsInstanceDef,
    /// The fraction ratio of public memory cells to the total memory cells.
    public_memory_fraction: u32,
    /// The number of memory units per step.
    memory_units_per_step: u32,
    /// Optional diluted pool instance definition.
    diluted_pool_instance_def: ?DilutedPoolInstanceDef,
    /// The number of trace columns.
    n_trace_columns: u32,
    /// The CPU instance definition.
    cpu_instance_def: CpuInstanceDef,

    /// Initializes a 'plain' layout instance configuration with default parameters.
    ///
    /// Returns a new `CairoLayout` structure representing the 'plain' layout configuration,
    /// setting specific values for CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 16
    /// - `public_memory_fraction`: 4
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 8
    /// - Other instances set to default or null.
    pub fn plainInstance() Self {
        return .{
            .name = "plain",
            .cpu_component_step = 1,
            .rc_units = 16,
            .builtins = BuiltinsInstanceDef.plain(),
            .public_memory_fraction = 4,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = null,
            .n_trace_columns = 8,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Initializes a 'small' layout instance configuration.
    ///
    /// Creates a `CairoLayout` structure representing the 'small' layout configuration,
    /// defining specific parameters for CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 16
    /// - `public_memory_fraction`: 4
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 25
    /// - Other instances set to default or null.
    pub fn smallInstance() Self {
        return .{
            .name = "small",
            .cpu_component_step = 1,
            .rc_units = 16,
            .builtins = BuiltinsInstanceDef.small(),
            .public_memory_fraction = 4,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = null,
            .n_trace_columns = 25,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Initializes a 'dex' layout instance configuration.
    ///
    /// Sets up a `CairoLayout` structure representing the 'dex' layout configuration,
    /// defining specific parameters for CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 4
    /// - `public_memory_fraction`: 4
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 22
    /// - Other instances set to default or null.
    pub fn dexInstance() Self {
        return .{
            .name = "dex",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = BuiltinsInstanceDef.dex(),
            .public_memory_fraction = 4,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = null,
            .n_trace_columns = 22,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Initializes a 'recursive' layout instance configuration.
    ///
    /// Constructs a `CairoLayout` structure for the 'recursive' layout, configuring
    /// CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 4
    /// - `public_memory_fraction`: 8
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 10
    /// - Includes initialized instances for Diluted Pool and CPU.
    pub fn recursiveInstance() Self {
        return .{
            .name = "recursive",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = BuiltinsInstanceDef.recursive(),
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = DilutedPoolInstanceDef.init(),
            .n_trace_columns = 10,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Initializes a 'starknet' layout instance configuration.
    ///
    /// Creates a `CairoLayout` structure tailored for StarkNet applications,
    /// configuring CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 4
    /// - `public_memory_fraction`: 8
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 10
    /// - Includes instances for StarkNet-specific built-ins, Diluted Pool, and CPU.
    pub fn starknetInstance() Self {
        return .{
            .name = "starknet",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = BuiltinsInstanceDef.starknet(),
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = DilutedPoolInstanceDef.from(2, 4, 16),
            .n_trace_columns = 10,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Initializes a 'starknet_with_keccak' layout instance.
    ///
    /// Configures a `CairoLayout` for StarkNet applications with Keccak hashing,
    /// setting up CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Requires an allocator to initialize Keccak instance.
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 4
    /// - `public_memory_fraction`: 8
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 15
    /// - Includes instances for Keccak, Diluted Pool, and CPU.
    pub fn starknetWithKeccakInstance(allocator: Allocator) !Self {
        return .{
            .name = "starknet_with_keccak",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = try BuiltinsInstanceDef.starknetWithKeccak(allocator),
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = DilutedPoolInstanceDef.init(),
            .n_trace_columns = 15,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Generates a layout instance named 'recursive_large_output'.
    ///
    /// Creates a configuration for Cairo programs optimized for extensive bitwise operations and Pedersen instances.
    /// Sets up CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 4
    /// - `public_memory_fraction`: 8
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 13
    /// - Includes instances for Builtins, Diluted Pool, and CPU.
    pub fn recursiveLargeOutputInstance() Self {
        return .{
            .name = "recursive_large_output",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = BuiltinsInstanceDef.recursiveLargeOutput(),
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = DilutedPoolInstanceDef.init(),
            .n_trace_columns = 13,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    // Constructs a layout instance called 'all_cairo'.
    ///
    /// Configures a layout optimized for a Cairo verifier program verified by another Cairo verifier.
    /// Sets up CPU, Range Check units, memory allocation, and trace columns.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 4
    /// - `public_memory_fraction`: 8
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 11
    /// - Includes instances for Builtins, Diluted Pool, and CPU.
    ///
    /// # Arguments
    ///
    /// - `allocator`: Allocator for memory management.
    ///
    /// Returns a layout instance configured for specific cryptographic and verification tasks.
    pub fn allCairoInstance(allocator: Allocator) !Self {
        return .{
            .name = "all_cairo",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = try BuiltinsInstanceDef.allCairo(allocator),
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = DilutedPoolInstanceDef.init(),
            .n_trace_columns = 11,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Generates a layout instance optimized for Solidity contracts.
    ///
    /// Configures a layout tailored for Solidity-based applications by setting up CPU, Range Check units,
    /// memory allocation, trace columns, and Builtins specifically designed for Solidity contracts.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 8
    /// - `public_memory_fraction`: 8
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 27
    /// - Includes instances for Builtins, Diluted Pool, and CPU.
    ///
    /// Returns a layout instance tailored for Solidity contract-specific verification tasks.
    pub fn allSolidityInstance() Self {
        return .{
            .name = "all_solidity",
            .cpu_component_step = 1,
            .rc_units = 8,
            .builtins = BuiltinsInstanceDef.allSolidity(),
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = DilutedPoolInstanceDef.init(),
            .n_trace_columns = 27,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Generates a dynamic layout instance for configurable setups.
    ///
    /// Creates a layout instance with customizable parameters, including CPU step count,
    /// Range Check units, memory allocation, trace columns, and predefined Builtins.
    ///
    /// Default parameters:
    /// - `cpu_component_step`: 1
    /// - `rc_units`: 16
    /// - `public_memory_fraction`: 8
    /// - `memory_units_per_step`: 8
    /// - `n_trace_columns`: 73
    /// - Includes instances for Builtins, Diluted Pool, and CPU.
    ///
    /// Returns a layout instance allowing configurable parameters for specialized verification tasks.
    pub fn dynamicInstance() Self {
        return .{
            .name = "dynamic",
            .cpu_component_step = 1,
            .rc_units = 16,
            .builtins = BuiltinsInstanceDef.dynamic(),
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = DilutedPoolInstanceDef.init(),
            .n_trace_columns = 73,
            .cpu_instance_def = CpuInstanceDef.init(),
        };
    }

    /// Deinitializes resources held by the layout's built-in instances.
    ///
    /// Frees up associated resources used by built-in instances within the layout.
    /// Ensures proper cleanup and release of memory resources.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the layout structure.
    ///
    /// Releases resources held by the built-in instances in the specified layout.
    pub fn deinit(self: *Self) void {
        self.builtins.deinit();
    }
};

test "CairoLayout: plainInstance" {
    try expectEqual(
        CairoLayout{
            .name = "plain",
            .cpu_component_step = 1,
            .rc_units = 16,
            .builtins = .{
                .output = false,
                .pedersen = null,
                .range_check = null,
                .ecdsa = null,
                .bitwise = null,
                .ec_op = null,
                .keccak = null,
                .poseidon = null,
            },
            .public_memory_fraction = 4,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = null,
            .n_trace_columns = 8,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.plainInstance(),
    );
}

test "CairoLayout: smallInstance" {
    try expectEqual(
        CairoLayout{
            .name = "small",
            .cpu_component_step = 1,
            .rc_units = 16,
            .builtins = .{
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
            .public_memory_fraction = 4,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = null,
            .n_trace_columns = 25,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.smallInstance(),
    );
}

test "CairoLayout: dexInstance" {
    try expectEqual(
        CairoLayout{
            .name = "dex",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = .{
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
            .public_memory_fraction = 4,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = null,
            .n_trace_columns = 22,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.dexInstance(),
    );
}

test "CairoLayout: recursiveInstance" {
    try expectEqual(
        CairoLayout{
            .name = "recursive",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = .{
                .output = true,
                .pedersen = .{
                    .ratio = 128,
                    .repetitions = 1,
                    .element_height = 256,
                    .element_bits = 252,
                    .n_inputs = 2,
                    .hash_limit = 3618502788666131213697322783095070105623107215331596699973092056135872020481,
                },
                .range_check = .{
                    .ratio = 8,
                    .n_parts = 8,
                },
                .ecdsa = null,
                .bitwise = .{
                    .ratio = 8,
                    .total_n_bits = 251,
                },
                .ec_op = null,
                .keccak = null,
                .poseidon = null,
            },
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = .{
                .units_per_step = 16,
                .spacing = 4,
                .n_bits = 16,
            },
            .n_trace_columns = 10,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.recursiveInstance(),
    );
}

test "CairoLayout: starknetInstance" {
    try expectEqual(
        CairoLayout{
            .name = "starknet",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = .{
                .output = true,
                .pedersen = .{
                    .ratio = 32,
                    .repetitions = 1,
                    .element_height = 256,
                    .element_bits = 252,
                    .n_inputs = 2,
                    .hash_limit = 3618502788666131213697322783095070105623107215331596699973092056135872020481,
                },
                .range_check = .{
                    .ratio = 16,
                    .n_parts = 8,
                },
                .ecdsa = .{
                    .ratio = 2048,
                    .repetitions = 1,
                    .height = 256,
                    .n_hash_bits = 251,
                },
                .bitwise = .{
                    .ratio = 64,
                    .total_n_bits = 251,
                },
                .ec_op = .{
                    .ratio = 1024,
                    .scalar_height = 256,
                    .scalar_bits = 252,
                },
                .keccak = null,
                .poseidon = .{ .ratio = 32 },
            },
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = .{
                .units_per_step = 2,
                .spacing = 4,
                .n_bits = 16,
            },
            .n_trace_columns = 10,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.starknetInstance(),
    );
}

test "CairoLayout: starknetWithKeccakInstance" {
    var actual = try CairoLayout.starknetWithKeccakInstance(std.testing.allocator);
    defer actual.deinit();

    var state_rep_keccak_expected = std.ArrayList(u32).init(std.testing.allocator);
    defer state_rep_keccak_expected.deinit();
    try state_rep_keccak_expected.appendNTimes(200, 8);

    try expectEqual(
        @as([]const u8, "starknet_with_keccak"),
        actual.name,
    );
    try expectEqual(
        @as(u32, 1),
        actual.cpu_component_step,
    );
    try expectEqual(
        @as(u32, 4),
        actual.rc_units,
    );
    try expectEqual(
        @as(u32, 4),
        actual.rc_units,
    );
    try expectEqual(
        @as(u32, 8),
        actual.public_memory_fraction,
    );
    try expectEqual(
        @as(u32, 8),
        actual.memory_units_per_step,
    );
    try expectEqual(
        @as(
            ?DilutedPoolInstanceDef,
            .{
                .units_per_step = 16,
                .spacing = 4,
                .n_bits = 16,
            },
        ),
        actual.diluted_pool_instance_def,
    );
    try expectEqual(
        @as(u32, 15),
        actual.n_trace_columns,
    );
    try expectEqual(
        CpuInstanceDef{ .safe_call = true },
        actual.cpu_instance_def,
    );

    // Builtin checks
    try expect(actual.builtins.output);
    try expectEqual(
        @as(
            ?PedersenInstanceDef,
            .{
                .ratio = 32,
                .repetitions = 1,
                .element_height = 256,
                .element_bits = 252,
                .n_inputs = 2,
                .hash_limit = 3618502788666131213697322783095070105623107215331596699973092056135872020481,
            },
        ),
        actual.builtins.pedersen,
    );
    try expectEqual(
        @as(
            ?RangeCheckInstanceDef,
            .{
                .ratio = 16,
                .n_parts = 8,
            },
        ),
        actual.builtins.range_check,
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
        actual.builtins.ecdsa,
    );
    try expectEqual(
        @as(
            ?BitwiseInstanceDef,
            .{
                .ratio = 64,
                .total_n_bits = 251,
            },
        ),
        actual.builtins.bitwise,
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
        actual.builtins.ec_op,
    );
    try expectEqual(
        @as(?u32, 2048),
        actual.builtins.keccak.?.ratio,
    );
    try expectEqual(
        @as(u32, 16),
        actual.builtins.keccak.?._instance_per_component,
    );
    try expectEqualSlices(
        u32,
        state_rep_keccak_expected.items,
        actual.builtins.keccak.?._state_rep.items,
    );

    try expectEqual(
        @as(
            ?PoseidonInstanceDef,
            .{ .ratio = 32 },
        ),
        actual.builtins.poseidon,
    );
}

test "CairoLayout: recursiveLargeOutputInstance" {
    try expectEqual(
        CairoLayout{
            .name = "recursive_large_output",
            .cpu_component_step = 1,
            .rc_units = 4,
            .builtins = .{
                .output = true,
                .pedersen = .{
                    .ratio = 32,
                    .repetitions = 1,
                    .element_height = 256,
                    .element_bits = 252,
                    .n_inputs = 2,
                    .hash_limit = 3618502788666131213697322783095070105623107215331596699973092056135872020481,
                },
                .range_check = .{
                    .ratio = 8,
                    .n_parts = 8,
                },
                .ecdsa = null,
                .bitwise = .{
                    .ratio = 8,
                    .total_n_bits = 251,
                },
                .ec_op = null,
                .keccak = null,
                .poseidon = null,
            },
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = .{
                .units_per_step = 16,
                .spacing = 4,
                .n_bits = 16,
            },
            .n_trace_columns = 13,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.recursiveLargeOutputInstance(),
    );
}

test "CairoLayout: allCairoInstance" {
    var actual = try CairoLayout.allCairoInstance(std.testing.allocator);
    defer actual.deinit();

    var state_rep_keccak_expected = std.ArrayList(u32).init(std.testing.allocator);
    defer state_rep_keccak_expected.deinit();
    try state_rep_keccak_expected.appendNTimes(200, 8);

    try expectEqual(
        @as([]const u8, "all_cairo"),
        actual.name,
    );
    try expectEqual(
        @as(u32, 1),
        actual.cpu_component_step,
    );
    try expectEqual(
        @as(u32, 4),
        actual.rc_units,
    );
    try expectEqual(
        @as(u32, 4),
        actual.rc_units,
    );
    try expectEqual(
        @as(u32, 8),
        actual.public_memory_fraction,
    );
    try expectEqual(
        @as(u32, 8),
        actual.memory_units_per_step,
    );
    try expectEqual(
        @as(
            ?DilutedPoolInstanceDef,
            .{
                .units_per_step = 16,
                .spacing = 4,
                .n_bits = 16,
            },
        ),
        actual.diluted_pool_instance_def,
    );
    try expectEqual(
        @as(u32, 11),
        actual.n_trace_columns,
    );
    try expectEqual(
        CpuInstanceDef{ .safe_call = true },
        actual.cpu_instance_def,
    );

    // Builtin checks
    try expect(actual.builtins.output);
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
        actual.builtins.pedersen,
    );
    try expectEqual(
        @as(
            ?RangeCheckInstanceDef,
            .{
                .ratio = 8,
                .n_parts = 8,
            },
        ),
        actual.builtins.range_check,
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
        actual.builtins.ecdsa,
    );
    try expectEqual(
        @as(
            ?BitwiseInstanceDef,
            .{
                .ratio = 16,
                .total_n_bits = 251,
            },
        ),
        actual.builtins.bitwise,
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
        actual.builtins.ec_op,
    );
    try expectEqual(
        @as(?u32, 2048),
        actual.builtins.keccak.?.ratio,
    );
    try expectEqual(
        @as(u32, 16),
        actual.builtins.keccak.?._instance_per_component,
    );
    try expectEqualSlices(
        u32,
        state_rep_keccak_expected.items,
        actual.builtins.keccak.?._state_rep.items,
    );

    try expectEqual(
        @as(
            ?PoseidonInstanceDef,
            .{ .ratio = 256 },
        ),
        actual.builtins.poseidon,
    );
}

test "CairoLayout: allSolidityInstance" {
    try expectEqual(
        CairoLayout{
            .name = "all_solidity",
            .cpu_component_step = 1,
            .rc_units = 8,
            .builtins = .{
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
                .bitwise = .{
                    .ratio = 256,
                    .total_n_bits = 251,
                },
                .ec_op = .{
                    .ratio = 256,
                    .scalar_height = 256,
                    .scalar_bits = 252,
                },
                .keccak = null,
                .poseidon = null,
            },
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = .{
                .units_per_step = 16,
                .spacing = 4,
                .n_bits = 16,
            },
            .n_trace_columns = 27,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.allSolidityInstance(),
    );
}

test "CairoLayout: dynamicInstance" {
    try expectEqual(
        CairoLayout{
            .name = "dynamic",
            .cpu_component_step = 1,
            .rc_units = 16,
            .builtins = .{
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
            .public_memory_fraction = 8,
            .memory_units_per_step = 8,
            .diluted_pool_instance_def = .{
                .units_per_step = 16,
                .spacing = 4,
                .n_bits = 16,
            },
            .n_trace_columns = 73,
            .cpu_instance_def = .{ .safe_call = true },
        },
        CairoLayout.dynamicInstance(),
    );
}
