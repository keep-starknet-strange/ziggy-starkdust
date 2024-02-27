const std = @import("std");
const Allocator = std.mem.Allocator;
const Tuple = std.meta.Tuple;

const MemorySegmentManager = @import("../../memory/segments.zig").MemorySegmentManager;
const CairoVM = @import("../../../vm/core.zig").CairoVM;
const MemoryError = @import("../../../vm/error.zig").MemoryError;
const InsufficientAllocatedCellsError = @import("../../../vm/error.zig").InsufficientAllocatedCellsError;
const BitwiseBuiltinRunner = @import("./bitwise.zig").BitwiseBuiltinRunner;
const EcOpBuiltinRunner = @import("./ec_op.zig").EcOpBuiltinRunner;
const HashBuiltinRunner = @import("./hash.zig").HashBuiltinRunner;
const KeccakBuiltinRunner = @import("./keccak.zig").KeccakBuiltinRunner;
const OutputBuiltinRunner = @import("./output.zig").OutputBuiltinRunner;
const PoseidonBuiltinRunner = @import("./poseidon.zig").PoseidonBuiltinRunner;
const RangeCheckBuiltinRunner = @import("./range_check.zig").RangeCheckBuiltinRunner;
const SegmentArenaBuiltinRunner = @import("./segment_arena.zig").SegmentArenaBuiltinRunner;
const SignatureBuiltinRunner = @import("./signature.zig").SignatureBuiltinRunner;
const Relocatable = @import("../../memory/relocatable.zig").Relocatable;
const MaybeRelocatable = @import("../../memory/relocatable.zig").MaybeRelocatable;
const Memory = @import("../../memory/memory.zig").Memory;
const KeccakInstanceDef = @import("../../types/keccak_instance_def.zig").KeccakInstanceDef;
const EcdsaInstanceDef = @import("../../types/ecdsa_instance_def.zig").EcdsaInstanceDef;
const BitwiseInstanceDef = @import("../../types/bitwise_instance_def.zig").BitwiseInstanceDef;
const EcOpInstanceDef = @import("../../types/ec_op_instance_def.zig").EcOpInstanceDef;

const ArrayList = std.ArrayList;

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;

/// The name of the output builtin.
pub const OUTPUT_BUILTIN_NAME = "output_builtin";

/// The name of the Pedersen hash builtin.
pub const HASH_BUILTIN_NAME = "pedersen_builtin";

/// The name of the range check builtin.
pub const RANGE_CHECK_BUILTIN_NAME = "range_check_builtin";

/// The name of the ECDSA signature verification builtin.
pub const SIGNATURE_BUILTIN_NAME = "ecdsa_builtin";

/// The name of the bitwise operations builtin.
pub const BITWISE_BUILTIN_NAME = "bitwise_builtin";

/// The name of the elliptic curve operations builtin.
pub const EC_OP_BUILTIN_NAME = "ec_op_builtin";

/// The name of the Keccak hash builtin.
pub const KECCAK_BUILTIN_NAME = "keccak_builtin";

/// The name of the Poseidon hash builtin.
pub const POSEIDON_BUILTIN_NAME = "poseidon_builtin";

/// The name of the segment arena builtin.
pub const SEGMENT_ARENA_BUILTIN_NAME = "segment_arena_builtin";

pub const BuiltinName = enum {
    /// Bitwise built-in runner for bitwise operations.
    Bitwise,
    /// EC Operation built-in runner for elliptic curve operations.
    EcOp,
    /// Hash built-in runner for hash operations.
    Hash,
    /// Output built-in runner for output operations.
    Output,
    /// Range Check built-in runner for range check operations.
    RangeCheck,
    /// Keccak built-in runner for Keccak operations.
    Keccak,
    /// Signature built-in runner for signature operations.
    Signature,
    /// Poseidon built-in runner for Poseidon operations.
    Poseidon,
    /// Segment Arena built-in runner for segment arena operations.
    SegmentArena,
};

/// Built-in runner
pub const BuiltinRunner = union(BuiltinName) {
    const Self = @This();

    /// Bitwise built-in runner for bitwise operations.
    Bitwise: BitwiseBuiltinRunner,
    /// EC Operation built-in runner for elliptic curve operations.
    EcOp: EcOpBuiltinRunner,
    /// Hash built-in runner for hash operations.
    Hash: HashBuiltinRunner,
    /// Output built-in runner for output operations.
    Output: OutputBuiltinRunner,
    /// Range Check built-in runner for range check operations.
    RangeCheck: RangeCheckBuiltinRunner,
    /// Keccak built-in runner for Keccak operations.
    Keccak: KeccakBuiltinRunner,
    /// Signature built-in runner for signature operations.
    Signature: SignatureBuiltinRunner,
    /// Poseidon built-in runner for Poseidon operations.
    Poseidon: PoseidonBuiltinRunner,
    /// Segment Arena built-in runner for segment arena operations.
    SegmentArena: SegmentArenaBuiltinRunner,

    /// Performs final stack operations based on the type of built-in runner.
    ///
    /// This function performs final stack operations based on the type of built-in runner. It takes
    /// the memory segments and a relocatable pointer as arguments and returns the final stack pointer
    /// after performing the necessary operations.
    ///
    /// # Arguments
    ///
    /// * `segments` - A pointer to the memory segment manager.
    /// * `pointer` - A relocatable pointer representing the current stack pointer.
    ///
    /// # Returns
    ///
    /// The final stack pointer after performing the necessary operations.
    ///
    /// # Errors
    ///
    /// Returns an error if any error occurs during the final stack operations.
    ///
    /// # Remarks
    ///
    /// This function is part of the built-in runner union and is used to perform final stack operations
    /// based on the specific type of built-in runner.
    pub fn finalStack(
        self: *Self,
        segments: *MemorySegmentManager,
        pointer: Relocatable,
    ) !Relocatable {
        return switch (self.*) {
            .SegmentArena => Relocatable{},
            inline else => |*builtin| builtin.finalStack(segments, pointer),
        };
    }

    /// Get the base value of the built-in runner.
    ///
    /// This function returns the base value specific to the type of built-in runner.
    ///
    /// # Returns
    ///
    /// The base value as a `usize`.
    pub fn base(self: *const Self) usize {
        return switch (self.*) {
            .SegmentArena => |*segment_arena| @intCast(segment_arena.base.segment_index),
            inline else => |*builtin| builtin.base,
        };
    }

    /// Retrieves the ratio associated with the built-in runner.
    ///
    /// For built-in runners other than SegmentArena and Output, this function returns the ratio
    /// specific to the type of built-in runner.
    ///
    /// For SegmentArena and Output built-in runners, `null` is returned, as they do not have an associated ratio.
    ///
    /// # Returns
    ///
    /// If applicable, the ratio associated with the built-in runner as a `u32`. If the built-in runner
    /// does not have an associated ratio, `null` is returned.
    pub fn ratio(self: *const BuiltinRunner) ?u32 {
        return switch (self.*) {
            .SegmentArena, .Output => null,
            inline else => |*builtin| builtin.ratio,
        };
    }

    /// Retrieves the number of cells per instance associated with the built-in runner.
    ///
    /// This function returns the number of memory cells per instance managed by the specific
    /// type of built-in runner. For built-in runners other than Output, it returns the value
    /// specific to the type of built-in runner. For Output built-in runners, it returns 0
    /// as Outputs do not have associated memory cells per instance.
    ///
    /// # Returns
    ///
    /// The number of cells per instance as a `u32`.
    pub fn cellsPerInstance(self: *const BuiltinRunner) u32 {
        return switch (self.*) {
            .Output => 0,
            inline else => |*builtin| builtin.cells_per_instance,
        };
    }

    /// Initializes a builtin with its required memory segments.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the MemorySegmentManager managing memory segments.
    pub fn initSegments(self: *Self, segments: *MemorySegmentManager) !void {
        switch (self.*) {
            inline else => |*builtin| try builtin.initSegments(segments),
        }
    }

    /// Derives necessary stack for a builtin.
    ///
    /// # Arguments
    ///
    ///  - `allocator`: The allocator to initialize the ArrayList.
    pub fn initialStack(self: *Self, allocator: Allocator) !ArrayList(MaybeRelocatable) {
        return switch (self.*) {
            inline else => |*builtin| try builtin.initialStack(allocator),
        };
    }

    /// Deduces memory cell information for the built-in runner.
    ///
    /// This function deduces memory cell information for the specific type of built-in runner.
    ///
    /// # Arguments
    ///
    /// - `address`: The address of the memory cell.
    /// - `memory`: The memory manager for the current context.
    ///
    /// # Returns
    ///
    /// A `MaybeRelocatable` representing the deduced memory cell information, or an error if deduction fails.
    pub fn deduceMemoryCell(
        self: *Self,
        allocator: Allocator,
        address: Relocatable,
        memory: *Memory,
    ) !?MaybeRelocatable {
        return switch (self.*) {
            .EcOp => |*ec| try ec.deduceMemoryCell(allocator, address, memory),
            .Keccak => |*keccak| try keccak.deduceMemoryCell(allocator, address, memory),
            .Poseidon => |*poseidon| try poseidon.deduceMemoryCell(allocator, address, memory),
            .Bitwise => |bitwise| try bitwise.deduceMemoryCell(address, memory),
            .Hash => |*hash| try hash.deduceMemoryCell(address, memory),
            inline else => |*builtin| builtin.deduceMemoryCell(address, memory),
        };
    }

    /// Retrieves memory accesses for a built-in runner.
    ///
    /// This function returns a list of memory accesses for a built-in runner, represented
    /// as an `ArrayList` of `Relocatable` objects.
    ///
    /// # Parameters
    ///
    /// - `allocator`: Allocator to allocate memory for the result ArrayList.
    /// - `vm`: Pointer to the CairoVM containing memory segments information.
    ///
    /// # Returns
    ///
    /// An ArrayList of Relocatable objects representing memory accesses.
    ///
    /// # Errors
    ///
    /// - `MemoryError.MissingSegmentUsedSizes`: Indicates missing segment used sizes in the CairoVM.
    pub fn getMemoryAccesses(
        self: *Self,
        allocator: Allocator,
        vm: *CairoVM,
    ) !ArrayList(Relocatable) {
        // Initialize the result ArrayList
        var result = ArrayList(Relocatable).init(allocator);
        // Defer deallocation of the result ArrayList if error
        errdefer result.deinit();

        // Switch based on the type of built-in runner
        switch (self.*) {
            // If the built-in runner is of type SegmentArena, return an empty result
            .SegmentArena => return result,
            // For other types of built-in runners
            else => |builtin| {
                // Get the base address of the built-in runner
                const b = builtin.base();
                // Get the segment size from CairoVM for the given base address
                const segment_size = vm.segments.getSegmentSize(@intCast(b)) orelse
                    return MemoryError.MissingSegmentUsedSizes;

                // Iterate through each memory access index within the segment size
                for (0..segment_size) |i| {
                    // Initialize a Relocatable object and append it to the result ArrayList
                    try result.append(Relocatable.init(@intCast(b), i));
                }
                // Return the ArrayList containing memory accesses
                return result;
            },
        }
    }

    /// Retrieves the memory segment addresses associated with the built-in runner.
    ///
    /// This function returns a `Tuple` containing the starting address and optional stop address
    /// for each memory segment used by the specific type of built-in runner. The stop address may
    /// be `null` if the built-in runner doesn't have a distinct stop address for its memory segment.
    ///
    /// # Returns
    ///
    /// A `Tuple` containing the memory segment addresses as follows:
    /// - The starting address of the memory segment.
    /// - An optional stop address of the memory segment (may be `null`).
    pub fn getMemorySegmentAddresses(self: *Self) Tuple(&.{ usize, ?usize }) {
        // TODO: fill-in missing builtins when implemented
        return switch (self.*) {
            .Signature, .SegmentArena => .{ 0, 0 },
            inline else => |*builtin| builtin.getMemorySegmentAddresses(),
        };
    }

    /// Retrieves the number of used memory cells associated with the built-in runner.
    ///
    /// This function calculates and returns the total number of used memory cells managed by
    /// the specific type of built-in runner. It utilizes the provided `segments` to determine
    /// the used cells based on the memory segments allocated.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` managing memory segments.
    ///
    /// # Returns
    ///
    /// The total number of used memory cells as a `usize`, or an error if calculation fails.
    pub fn getUsedCells(self: *Self, segments: *MemorySegmentManager) !usize {
        return switch (self.*) {
            .SegmentArena => 0,
            inline else => |*builtin| try builtin.getUsedCells(segments),
        };
    }

    /// Retrieves the number of allocated memory units associated with the built-in runner.
    ///
    /// This function calculates and returns the total number of allocated memory units managed by
    /// the specific type of built-in runner. It takes into account various factors such as ratio,
    /// current step, instances per component, and cells per instance to compute the allocation.
    ///
    /// # Arguments
    ///
    /// - `vm`: A pointer to the `CairoVM` containing relevant information for computation.
    ///
    /// # Returns
    ///
    /// The total number of allocated memory units as a `usize`, or an error if calculation fails.
    ///
    /// # Errors
    ///
    /// Returns an error if any error occurs during the computation.
    ///
    pub fn getAllocatedMemoryUnits(self: *Self, vm: *CairoVM) !usize {
        switch (self.*) {
            // For Output and SegmentArena built-in runners, return 0 as they do not allocate memory units
            .Output, .SegmentArena => return 0,
            // For other types of built-in runners
            else => {
                // Check if the built-in runner has a ratio
                if (self.ratio()) |r| {
                    // Ensure that the current step is sufficient for allocation based on the ratio
                    if (vm.current_step < r * self.getInstancesPerComponent())
                        return InsufficientAllocatedCellsError.MinStepNotReached;

                    // Calculate the value based on the current step and ratio
                    const value: usize = std.math.divExact(usize, vm.current_step, r) catch
                        return MemoryError.ErrorCalculatingMemoryUnits;

                    // Return the value multiplied by the cells per instance
                    return value * self.cellsPerInstance();
                }

                // Calculate instances and components based on used cells and instances per component
                const instances: usize = (try self.getUsedCells(vm.segments)) / self.cellsPerInstance();
                const components: usize = @intCast(std.math.ceilPowerOfTwoPromote(
                    usize,
                    @intCast((instances / self.getInstancesPerComponent())),
                ));

                // Return the calculated allocation based on cells per instance, instances per component, and components
                return @as(usize, @intCast(self.cellsPerInstance())) *
                    @as(usize, @intCast(self.getInstancesPerComponent())) *
                    components;
            },
        }
    }

    /// Retrieves the number of used cells and allocated size associated with the built-in runner.
    ///
    /// This function calculates and returns a tuple containing the number of used cells and the allocated
    /// size managed by the specific type of built-in runner based on the provided `CairoVM` instance.
    ///
    /// # Arguments
    ///
    /// - `vm`: A pointer to the `CairoVM` instance.
    ///
    /// # Returns
    ///
    /// A tuple containing the number of used cells and the allocated size as follows:
    /// - The number of used cells as a `usize`.
    /// - The allocated size as an optional `usize`. If the built-in runner doesn't have an allocated size,
    ///   the size will be `null`.
    ///
    /// # Errors
    ///
    /// Returns an error if any error occurs during the calculation.
    ///
    /// # Remarks
    ///
    /// This function is used to determine the usage and allocation status of memory cells associated
    /// with the specific type of built-in runner.
    pub fn getUsedCellsAndAllocatedSize(self: *Self, vm: *CairoVM) !Tuple(&.{ usize, ?usize }) {
        switch (self.*) {
            // For output and segment arena built-in runners
            .Output, .SegmentArena => {
                // Calculate the number of used cells
                const used = try self.getUsedCells(vm.segments);
                // Return a tuple with both used cells and allocated size set to the same value
                return .{ used, used };
            },
            else => {
                // Calculate the number of used cells
                const used = try self.getUsedCells(vm.segments);
                // Calculate the allocated size
                const size = try self.getAllocatedMemoryUnits(vm);

                // Check if the used cells exceed the allocated size
                if (used > size) return InsufficientAllocatedCellsError.BuiltinCells;

                // Return a tuple containing the number of used cells and the allocated size
                return .{ used, size };
            },
        }
    }

    /// Retrieves the number of used permanent range check units associated with the built-in runner.
    ///
    /// This function calculates and returns the total number of used permanent range check units managed by
    /// the specific type of built-in runner based on the provided `CairoVM` instance.
    ///
    /// # Arguments
    ///
    /// - `vm`: A pointer to the `CairoVM` instance.
    ///
    /// # Returns
    ///
    /// The total number of used permanent range check units as a `usize`.
    ///
    /// # Remarks
    ///
    /// This function is used to determine the usage of permanent range check units associated
    /// with the specific type of built-in runner.
    pub fn getUsedPermRangeCheckUnits(self: *Self, vm: *CairoVM) !usize {
        return switch (self.*) {
            // For range check built-in runners
            .RangeCheck => |range_check| {
                // Get the number of used cells and allocated size tuple
                const tuple = try self.getUsedCellsAndAllocatedSize(vm);
                // Extract the number of used cells from the tuple
                const usedCells = tuple[0];
                // Calculate and return the total number of used permanent range check units
                return usedCells * range_check.n_parts;
            },
            else => 0,
        };
    }

    /// Calculates the number of used diluted check units associated with the built-in runner.
    ///
    /// This function takes into account the type of built-in runner and calculates the number of
    /// used diluted check units based on the specific characteristics of each type.
    ///
    /// # Arguments
    ///
    /// - `self`: A pointer to the `BuiltinRunner` instance.
    /// - `allocator`: The allocator used for memory allocation.
    /// - `diluted_spacing`: The spacing between diluted check units.
    /// - `diluted_n_bits`: The number of bits per diluted check unit.
    ///
    /// # Returns
    ///
    /// The number of used diluted check units.
    ///
    /// # Errors
    ///
    /// This function returns an error if the calculation fails or if the built-in runner type
    /// does not support diluted check units.
    pub fn getUsedDilutedCheckUnits(
        self: *Self,
        allocator: Allocator,
        diluted_spacing: u32,
        diluted_n_bits: u32,
    ) !usize {
        return switch (self.*) {
            .Bitwise => |*bitwise| bitwise.getUsedDilutedCheckUnits(allocator, diluted_spacing, diluted_n_bits),
            .Keccak => KeccakBuiltinRunner.getUsedDilutedCheckUnits(diluted_n_bits),
            else => 0,
        };
    }

    /// Retrieves the number of used instances associated with the built-in runner.
    ///
    /// This function calculates and returns the total number of used instances managed by
    /// the specific type of built-in runner. It utilizes the provided `segments` to determine
    /// the used instances based on the memory segments allocated.
    ///
    /// # Arguments
    ///
    /// - `segments`: A pointer to the `MemorySegmentManager` managing memory segments.
    ///
    /// # Returns
    ///
    /// The total number of used instances as a `usize`, or an error if calculation fails.
    pub fn getUsedInstances(self: *Self, segments: *MemorySegmentManager) !usize {
        return switch (self.*) {
            .SegmentArena => 0,
            inline else => |*builtin| try builtin.getUsedInstances(segments),
        };
    }

    /// Retrieves the number of instances per component for the built-in runner.
    ///
    /// This function returns the number of instances per component for the specific type of
    /// built-in runner. Each built-in runner may have a different number of instances per
    /// component based on its configuration and purpose.
    ///
    /// # Returns
    ///
    /// A `usize` representing the number of instances per component for the built-in runner.
    pub fn getInstancesPerComponent(self: *Self) u32 {
        return switch (self.*) {
            .SegmentArena, .Output => 1,
            inline else => |*builtin| builtin.instances_per_component,
        };
    }

    /// Gets the name of the built-in runner.
    ///
    /// This function returns the name associated with the specific type of built-in runner.
    ///
    /// # Returns
    ///
    /// A null-terminated byte slice representing the name of the built-in runner.
    pub fn name(self: *Self) []const u8 {
        return switch (self.*) {
            .Bitwise => BITWISE_BUILTIN_NAME,
            .EcOp => EC_OP_BUILTIN_NAME,
            .Hash => HASH_BUILTIN_NAME,
            .Output => OUTPUT_BUILTIN_NAME,
            .RangeCheck => RANGE_CHECK_BUILTIN_NAME,
            .Keccak => KECCAK_BUILTIN_NAME,
            .Signature => SIGNATURE_BUILTIN_NAME,
            .Poseidon => POSEIDON_BUILTIN_NAME,
            .SegmentArena => SEGMENT_ARENA_BUILTIN_NAME,
        };
    }

    /// Adds a validation rule to the built-in runner for memory validation.
    ///
    /// This method is used to add a validation rule specific to the type of built-in runner.
    /// For certain built-ins, like the Range Check built-in, additional memory validation rules may
    /// be necessary to ensure proper execution.
    ///
    /// # Arguments
    ///
    /// - `memory`: A pointer to the Memory manager for the current context.
    ///
    /// # Errors
    ///
    /// An error is returned if adding the validation rule fails.
    pub fn addValidationRule(self: *Self, memory: *Memory) !void {
        switch (self.*) {
            .RangeCheck => |*range_check| try range_check.addValidationRule(memory),
            else => {},
        }
    }

    /// Retrieves the usage statistics associated with range checks, if applicable.
    ///
    /// This function retrieves the usage statistics associated with range checks, if applicable. It returns a `Tuple`
    /// containing information about the number of range checks performed and the total memory usage attributed to these
    /// checks.
    ///
    /// # Parameters
    ///
    /// * `memory` - A pointer to the `Memory` manager for the current context.
    ///
    /// # Returns
    ///
    /// * If the built-in runner is of type `RangeCheck`, the function returns a `Tuple` containing:
    ///     - The number of range checks performed.
    ///     - The total memory usage attributed to these checks.
    /// * If the built-in runner is not of type `RangeCheck`, the function returns `null`.
    ///
    /// # Errors
    ///
    /// Returns an error if any error occurs during the retrieval process.
    ///
    /// # Remarks
    ///
    /// This function is part of the `BuiltinRunner` union(enum) and is used to retrieve usage statistics associated
    /// specifically with range checks.
    pub fn getRangeCheckUsage(self: *const Self, memory: *Memory) ?std.meta.Tuple(&.{ usize, usize }) {
        return switch (self.*) {
            .RangeCheck => |*range_check| range_check.getRangeCheckUsage(memory),
            else => null,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .EcOp => |*ec_op| ec_op.deinit(),
            .Hash => |*hash| hash.deinit(),
            .Keccak => |*keccak| keccak.deinit(),
            .Signature => |*signature| signature.deinit(),
            else => {},
        }
    }
};

test "BuiltinRunner: getRangeCheckUsage with range check builtin" {
    // Initialize a BuiltinRunner for range check operations.
    var builtin: BuiltinRunner = .{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) };

    // Initialize a Memory instance named `mem`.
    var mem = try Memory.init(std.testing.allocator);
    defer mem.deinit();

    // Set up memory for `mem`.
    try mem.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    // Test if the getRangeCheckUsage method of the range check builtin returns the expected tuple.
    try expectEqual(
        @as(?Tuple(&.{ usize, usize }), .{ 0, 4 }),
        builtin.getRangeCheckUsage(mem),
    );
}

test "BuiltinRunner: getRangeCheckUsage with output builtin" {
    // Initialize a BuiltinRunner for output operations.
    var builtin: BuiltinRunner = .{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) };

    // Initialize a Memory instance named `mem`.
    var mem = try Memory.init(std.testing.allocator);
    defer mem.deinit();

    // Set up memory for `mem`.
    try mem.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    // Test if the getRangeCheckUsage method of the output builtin returns null.
    try expectEqual(
        null,
        builtin.getRangeCheckUsage(mem),
    );
}

test "BuiltinRunner: getRangeCheckUsage with hash builtin" {
    // Initialize a BuiltinRunner for hash operations.
    var builtin: BuiltinRunner = .{ .Hash = HashBuiltinRunner.init(std.testing.allocator, 256, true) };
    defer builtin.deinit();

    // Initialize a Memory instance named `mem`.
    var mem = try Memory.init(std.testing.allocator);
    defer mem.deinit();

    // Set up memory for `mem`.
    try mem.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    // Test if the getRangeCheckUsage method of the hash builtin returns null.
    try expectEqual(
        null,
        builtin.getRangeCheckUsage(mem),
    );
}

test "BuiltinRunner: getRangeCheckUsage with elliptic curve operations builtin" {
    // Initialize a BuiltinRunner for elliptic curve operations.
    var builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };
    defer builtin.deinit();

    // Initialize a Memory instance named `mem`.
    var mem = try Memory.init(std.testing.allocator);
    defer mem.deinit();

    // Set up memory for `mem`.
    try mem.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    // Test if the getRangeCheckUsage method of the elliptic curve operations builtin returns null.
    try expectEqual(
        null,
        builtin.getRangeCheckUsage(mem),
    );
}

test "BuiltinRunner: getRangeCheckUsage with bitwise builtin" {
    // Initialize a BuiltinRunner for bitwise operations.
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };
    defer builtin.deinit();

    // Initialize a Memory instance named `mem`.
    var mem = try Memory.init(std.testing.allocator);
    defer mem.deinit();

    // Set up memory for `mem`.
    try mem.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    defer mem.deinitData(std.testing.allocator);

    // Test if the getRangeCheckUsage method of the bitwise operations builtin returns null.
    try expectEqual(
        null,
        builtin.getRangeCheckUsage(mem),
    );
}

test "BuiltinRunner: ratio method" {
    // Initialize a BuiltinRunner for bitwise operations.
    const bitwise_builtin: BuiltinRunner = .{ .Bitwise = .{} };
    // Test the ratio method for bitwise_builtin.
    // We expect the ratio to be 256.
    try expectEqual(@as(?u32, 256), bitwise_builtin.ratio());

    // Initialize a BuiltinRunner for EC operations.
    var ec_op_builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };
    // Defer deinitialization of ec_op_builtin.
    defer ec_op_builtin.deinit();
    // Test the ratio method for ec_op_builtin.
    // We expect the ratio to be 256.
    try expectEqual(@as(?u32, 256), ec_op_builtin.ratio());

    // Initialize a BuiltinRunner for hash operations.
    var hash_builtin: BuiltinRunner = .{
        .Hash = HashBuiltinRunner.init(
            std.testing.allocator,
            100,
            true,
        ),
    };
    // Defer deinitialization of hash_builtin.
    defer hash_builtin.deinit();
    // Test the ratio method for hash_builtin.
    // We expect the ratio to be 100.
    try expectEqual(@as(?u32, 100), hash_builtin.ratio());

    // Initialize a BuiltinRunner for output operations.
    var output_builtin: BuiltinRunner = .{
        .Output = OutputBuiltinRunner.initDefault(std.testing.allocator),
    };
    defer output_builtin.deinit(); // Defer deinitialization of output_builtin.
    // Test the ratio method for output_builtin.
    // Since output operations do not have an associated ratio, we expect null.
    try expectEqual(null, output_builtin.ratio());

    // Initialize a BuiltinRunner for range check operations.
    const rangecheck_builtin: BuiltinRunner = .{ .RangeCheck = .{} };
    // Test the ratio method for rangecheck_builtin.
    // We expect the ratio to be 8.
    try expectEqual(@as(?u32, 8), rangecheck_builtin.ratio());

    // Initialize a Keccak instance definition.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);
    // Initialize a BuiltinRunner for Keccak operations.
    var keccak_builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };
    // Defer deinitialization of keccak_builtin.
    defer keccak_builtin.deinit();
    // Test the ratio method for keccak_builtin.
    // We expect the ratio to be 2048.
    try expectEqual(@as(?u32, 2048), keccak_builtin.ratio());
}

test "BuiltinRunner: cellsPerInstance method" {
    // Initialize a BuiltinRunner for bitwise operations.
    const bitwise_builtin: BuiltinRunner = .{ .Bitwise = .{} };
    // Test the cellsPerInstance method for bitwise_builtin.
    // We expect the number of cells per instance to be 256.
    try expectEqual(@as(u32, 5), bitwise_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for EC operations.
    var ec_op_builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };
    // Defer deinitialization of ec_op_builtin.
    defer ec_op_builtin.deinit();
    // Test the cellsPerInstance method for ec_op_builtin.
    // We expect the number of cells per instance to be 256.
    try expectEqual(@as(u32, 7), ec_op_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for hash operations.
    var hash_builtin: BuiltinRunner = .{
        .Hash = HashBuiltinRunner.init(
            std.testing.allocator,
            100,
            true,
        ),
    };
    // Defer deinitialization of hash_builtin.
    defer hash_builtin.deinit();
    // Test the cellsPerInstance method for hash_builtin.
    // We expect the number of cells per instance to be 100.
    try expectEqual(@as(?u32, 3), hash_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for output operations.
    var output_builtin: BuiltinRunner = .{
        .Output = OutputBuiltinRunner.initDefault(std.testing.allocator),
    };
    // Defer deinitialization of output_builtin.
    defer output_builtin.deinit();
    // Test the cellsPerInstance method for output_builtin.
    // Since output operations do not have associated cells per instance, we expect 0.
    try expectEqual(@as(u32, 0), output_builtin.cellsPerInstance());

    // Initialize a BuiltinRunner for range check operations.
    const rangecheck_builtin: BuiltinRunner = .{ .RangeCheck = .{} };
    // Test the cellsPerInstance method for rangecheck_builtin.
    // We expect the number of cells per instance to be 8.
    try expectEqual(@as(u32, 1), rangecheck_builtin.cellsPerInstance());

    // Initialize a Keccak instance definition.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);
    // Initialize a BuiltinRunner for Keccak operations.
    var keccak_builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };
    // Defer deinitialization of keccak_builtin.
    defer keccak_builtin.deinit();
    // Test the cellsPerInstance method for keccak_builtin.
    // We expect the number of cells per instance to be 2048.
    try expectEqual(@as(u32, 16), keccak_builtin.cellsPerInstance());
}

test "BuiltinRunner: finalStack" {
    // Initialize Cairo VM
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    defer vm.deinit();

    // Initialize ArrayList for built-in runners
    var builtins = ArrayList(BuiltinRunner).init(std.testing.allocator);
    defer builtins.deinit();

    // Initialize various built-in runners
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);
    var ecdsa_instance_def = EcdsaInstanceDef.init(512);
    var bitwise_instance_def: BitwiseInstanceDef = .{};

    try builtins.append(.{ .Bitwise = BitwiseBuiltinRunner.init(&bitwise_instance_def, false) });
    try builtins.append(.{ .Hash = HashBuiltinRunner.init(std.testing.allocator, 1, false) });
    try builtins.append(.{ .Output = OutputBuiltinRunner.init(std.testing.allocator, false) });
    try builtins.append(.{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, false) });
    try builtins.append(.{ .Keccak = KeccakBuiltinRunner.init(std.testing.allocator, &keccak_instance_def, false) });
    try builtins.append(.{ .Signature = SignatureBuiltinRunner.init(std.testing.allocator, &ecdsa_instance_def, false) });

    // Iterate through each built-in runner and test its `finalStack` function
    for (builtins.items) |*builtin| {
        // Run the built-in runner and verify final stack pointer
        try expectEqual(
            vm.run_context.ap.*, // Current stack pointer
            builtin.finalStack(vm.segments, vm.run_context.ap.*), // Final stack pointer after running the built-in runner
        );

        // Deinitialize the built-in runner
        defer builtin.deinit();
    }
}

test "BuiltinRunner: getMemoryAccesses with missing segment used sizes" {
    // Initialize Cairo VM
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    // Ensure Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Initialize a BuiltinRunner instance with Bitwise runner
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };

    // Expecting an error of type MemoryError.MissingSegmentUsedSizes
    try expectError(
        MemoryError.MissingSegmentUsedSizes,
        builtin.getMemoryAccesses(std.testing.allocator, &vm),
    );
}

test "BuiltinRunner: getMemoryAccesses with empty access" {
    // Initialize Cairo VM
    var vm = try CairoVM.init(
        std.testing.allocator,
        .{},
    );
    // Ensure Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set segment used sizes to simulate empty memory access
    try vm.segments.segment_used_sizes.put(0, 0);

    // Initialize a BuiltinRunner instance with Bitwise runner
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };

    // Retrieve memory accesses from the built-in runner
    var actual = try builtin.getMemoryAccesses(std.testing.allocator, &vm);
    // Ensure actual result is deallocated at the end of the test
    defer actual.deinit();

    // Expecting the actual memory accesses to be empty
    try expect(actual.items.len == 0);
}

test "BuiltinRunner: getMemoryAccesses with real data" {
    // Initialize Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set segment used sizes to simulate real memory access data
    try vm.segments.segment_used_sizes.put(0, 4);

    // Initialize a BuiltinRunner instance with Bitwise runner
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };

    // Retrieve memory accesses from the built-in runner
    var actual = try builtin.getMemoryAccesses(std.testing.allocator, &vm);
    defer actual.deinit();

    // Create an ArrayList to hold the expected memory accesses
    var expected = ArrayList(Relocatable).init(std.testing.allocator);
    defer expected.deinit();
    try expected.append(Relocatable.init(0, 0));
    try expected.append(Relocatable.init(0, 1));
    try expected.append(Relocatable.init(0, 2));
    try expected.append(Relocatable.init(0, 3));

    // Verify that the actual memory accesses match the expected memory accesses
    try expectEqualSlices(Relocatable, expected.items, actual.items);
}

test "BuiltinRunner: getAllocatedMemoryUnits with Keccak builtin with items" {
    // Initialize an ArrayList to represent the state representation
    var state_rep = ArrayList(u32).init(std.testing.allocator);
    // Ensure the ArrayList is deallocated at the end of the test
    defer state_rep.deinit();
    // Append 200 elements with the value 8 to the state representation ArrayList
    try state_rep.appendNTimes(200, 8);

    // Initialize a KeccakInstanceDef with a capacity of 10 and the state representation ArrayList
    var keccak_instance_def = KeccakInstanceDef.init(10, state_rep);

    // Initialize a BuiltinRunner union with the KeccakBuiltinRunner variant
    var builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();
    // Set the current step of the Cairo VM to 160
    vm.current_step = 160;

    // Verify that the result of getAllocatedMemoryUnits(&vm) is equal to 256 when casted to usize
    try expectEqual(@as(usize, 256), try builtin.getAllocatedMemoryUnits(&vm));
}

test "BuiltinRunner: getAllocatedMemoryUnits with Keccak builtin and minimum step not reached" {
    // Initialize an ArrayList to represent the state representation
    var state_rep = ArrayList(u32).init(std.testing.allocator);
    // Ensure the ArrayList is deallocated at the end of the test
    defer state_rep.deinit();
    // Append 200 elements with the value 8 to the state representation ArrayList
    try state_rep.appendNTimes(200, 8);

    // Initialize a KeccakInstanceDef with a capacity of 10 and the state representation ArrayList
    var keccak_instance_def = KeccakInstanceDef.init(10, state_rep);

    // Initialize a BuiltinRunner union with the KeccakBuiltinRunner variant
    var builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();
    // Set the current step of the Cairo VM to 10
    vm.current_step = 10;

    // Verify that calling getAllocatedMemoryUnits(&vm) results in an InsufficientAllocatedCellsError
    try expectError(
        InsufficientAllocatedCellsError.MinStepNotReached,
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BuiltinRunner: getAllocatedMemoryUnits with output builtin" {
    // Initialize a BuiltinRunner union with the OutputBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .Output = OutputBuiltinRunner.init(std.testing.allocator, true) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Verify that the result of getAllocatedMemoryUnits(&vm) is equal to 0 when casted to usize
    try expectEqual(
        @as(usize, 0),
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BuiltinRunner: getAllocatedMemoryUnits with range check builtin" {
    // Initialize a BuiltinRunner union with the RangeCheckBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 8
    vm.current_step = 8;

    // Verify that the result of getAllocatedMemoryUnits(&vm) is equal to 1 when casted to usize
    try expectEqual(
        @as(usize, 1),
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BuiltinRunner: getAllocatedMemoryUnits with hash builtin" {
    // Initialize a BuiltinRunner union with the HashBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .Hash = HashBuiltinRunner.init(std.testing.allocator, 1, true) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 1
    vm.current_step = 1;

    // Verify that the result of getAllocatedMemoryUnits(&vm) is equal to 3 when casted to usize
    try expectEqual(
        @as(usize, 3),
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BuiltinRunner: getAllocatedMemoryUnits with bitwise builtin" {
    // Initialize a BuiltinRunner union with the BitwiseBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 256
    vm.current_step = 256;

    // Verify that the result of getAllocatedMemoryUnits(&vm) is equal to 5 when casted to usize
    try expectEqual(
        @as(usize, 5),
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BuiltinRunner: getAllocatedMemoryUnits with elliptic curve operation builtin" {
    // Initialize a BuiltinRunner union with the EcOpBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 256
    vm.current_step = 256;

    // Verify that the result of getAllocatedMemoryUnits(&vm) is equal to 7 when casted to usize
    try expectEqual(
        @as(usize, 7),
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BuiltinRunner: getAllocatedMemoryUnits with keccak builtin" {
    // Initialize a default Keccak instance definition
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);

    // Initialize a BuiltinRunner union with the KeccakBuiltinRunner variant
    var builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };
    // Ensure proper deallocation of the built-in runner at the end of the test
    defer builtin.deinit();

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 32768
    vm.current_step = 32768;

    // Verify that the result of getAllocatedMemoryUnits(&vm) is equal to 256 when casted to usize
    try expectEqual(
        @as(usize, 256),
        builtin.getAllocatedMemoryUnits(&vm),
    );
}

test "BuiltinRunner:getRangeCheckUsage with range check builtin" {
    // Initialize a `BuiltinRunner` with a `RangeCheckBuiltinRunner`.
    var builtin: BuiltinRunner = .{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) };

    // Initialize a `Memory` instance for testing.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure the memory instance is deallocated properly at the end of the test.
    defer memory.deinit();

    // Set up memory segments with specific data for testing range checks.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    // Ensure the memory data is deallocated properly at the end of the test.
    defer memory.deinitData(std.testing.allocator);

    // Test the `getRangeCheckUsage` function
    try expectEqual(
        @as(?std.meta.Tuple(&.{ usize, usize }), .{ 0, 4 }),
        builtin.getRangeCheckUsage(memory),
    );
}

test "BuiltinRunner:getRangeCheckUsage with output builtin" {
    // Initialize a `BuiltinRunner` with an `OutputBuiltinRunner`.
    var builtin: BuiltinRunner = .{ .Output = OutputBuiltinRunner.init(std.testing.allocator, true) };

    // Initialize a `Memory` instance for testing.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure the memory instance is deallocated properly at the end of the test.
    defer memory.deinit();

    // Set up memory segments with specific data for testing output builtin.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    // Ensure the memory data is deallocated properly at the end of the test.
    defer memory.deinitData(std.testing.allocator);

    // Test the `getRangeCheckUsage` function of the `BuiltinRunner`
    try expectEqual(null, builtin.getRangeCheckUsage(memory));
}

test "BuiltinRunner:getRangeCheckUsage with hash builtin" {
    // Initialize a `BuiltinRunner` with a `HashBuiltinRunner`.
    var builtin: BuiltinRunner = .{ .Hash = HashBuiltinRunner.init(std.testing.allocator, 256, true) };

    // Initialize a `Memory` instance for testing.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure the memory instance is deallocated properly at the end of the test.
    defer memory.deinit();

    // Set up memory segments with specific data for testing hash builtin.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    // Ensure the memory data is deallocated properly at the end of the test.
    defer memory.deinitData(std.testing.allocator);

    // Test the `getRangeCheckUsage` function of the `BuiltinRunner`.
    try expectEqual(null, builtin.getRangeCheckUsage(memory));
}

test "BuiltinRunner:getRangeCheckUsage with elliptic curve operation builtin" {
    // Initialize a `BuiltinRunner` with an `EcOpBuiltinRunner`.
    var builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };

    // Initialize a `Memory` instance for testing.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure the memory instance is deallocated properly at the end of the test.
    defer memory.deinit();

    // Set up memory segments with specific data for testing elliptic curve operation builtin.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    // Ensure the memory data is deallocated properly at the end of the test.
    defer memory.deinitData(std.testing.allocator);

    // Test the `getRangeCheckUsage` function of the `BuiltinRunner`.
    try expectEqual(null, builtin.getRangeCheckUsage(memory));
}

test "BuiltinRunner:getRangeCheckUsage with bitwise builtin" {
    // Initialize a `BuiltinRunner` with a `Bitwise` variant.
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };

    // Initialize a `Memory` instance for testing.
    var memory = try Memory.init(std.testing.allocator);
    // Ensure the memory instance is deallocated properly at the end of the test.
    defer memory.deinit();

    // Set up memory segments with specific data for testing bitwise builtin.
    try memory.setUpMemory(
        std.testing.allocator,
        .{
            .{ .{ 0, 0 }, .{1} },
            .{ .{ 0, 1 }, .{2} },
            .{ .{ 0, 2 }, .{3} },
            .{ .{ 0, 3 }, .{4} },
        },
    );
    // Ensure the memory data is deallocated properly at the end of the test.
    defer memory.deinitData(std.testing.allocator);

    // Test the `getRangeCheckUsage` function of the `BuiltinRunner`.
    try expectEqual(null, builtin.getRangeCheckUsage(memory));
}

test "BuiltinRunner:getUsedPermRangeCheckUnits with bitwise builtin" {
    // Initialize a `BuiltinRunner` with a `Bitwise` variant.
    // This sets up the test scenario where the built-in runner is of type bitwise.
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 8
    // This simulates the current step of the VM for the test scenario.
    vm.current_step = 8;

    // Set segment used sizes to simulate real memory access data
    // Here, the segment used size at index 0 is set to 5, indicating memory usage.
    try vm.segments.segment_used_sizes.put(0, 5);

    // Call the `getUsedPermRangeCheckUnits` function of the `builtin` instance
    try expectEqual(@as(usize, 0), builtin.getUsedPermRangeCheckUnits(&vm));
}

test "BuiltinRunner:getUsedPermRangeCheckUnits with elliptic curve operation builtin" {
    // Initialize a `BuiltinRunner` with an `EcOp` variant.
    // This sets up the test scenario where the built-in runner is of type elliptic curve operation.
    var builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 8
    // This simulates the current step of the VM for the test scenario.
    vm.current_step = 8;

    // Set segment used sizes to simulate real memory access data
    // Here, the segment used size at index 0 is set to 5, indicating memory usage.
    try vm.segments.segment_used_sizes.put(0, 5);

    // Call the `getUsedPermRangeCheckUnits` function of the `builtin` instance
    // This function retrieves the number of used permanent range check units associated with the built-in runner.
    try expectEqual(@as(usize, 0), builtin.getUsedPermRangeCheckUnits(&vm));
}

test "BuiltinRunner:getUsedPermRangeCheckUnits with hash builtin" {
    // Initialize a `BuiltinRunner` with a `Hash` variant.
    // This sets up the test scenario where the built-in runner is of type hash operation.
    var builtin: BuiltinRunner = .{ .Hash = HashBuiltinRunner.init(std.testing.allocator, 8, true) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 8
    // This simulates the current step of the VM for the test scenario.
    vm.current_step = 8;

    // Set segment used sizes to simulate real memory access data
    // Here, the segment used size at index 0 is set to 5, indicating memory usage.
    try vm.segments.segment_used_sizes.put(0, 5);

    // Call the `getUsedPermRangeCheckUnits` function of the `builtin` instance
    // This function retrieves the number of used permanent range check units associated with the built-in runner.
    try expectEqual(@as(usize, 0), builtin.getUsedPermRangeCheckUnits(&vm));
}

test "BuiltinRunner:getUsedPermRangeCheckUnits with output builtin" {
    // Initialize a `BuiltinRunner` with an `OutputBuiltinRunner` variant.
    // This sets up the test scenario where the built-in runner is of type output operation.
    var builtin: BuiltinRunner = .{ .Output = OutputBuiltinRunner.init(std.testing.allocator, true) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 8
    // This simulates the current step of the VM for the test scenario.
    vm.current_step = 8;

    // Set segment used sizes to simulate real memory access data
    // Here, the segment used size at index 0 is set to 5, indicating memory usage.
    try vm.segments.segment_used_sizes.put(0, 5);

    // Call the `getUsedPermRangeCheckUnits` function of the `builtin` instance
    // This function retrieves the number of used permanent range check units associated with the built-in runner.
    try expectEqual(@as(usize, 0), builtin.getUsedPermRangeCheckUnits(&vm));
}

test "BuiltinRunner:getUsedPermRangeCheckUnits with range check builtin" {
    // Initialize a `BuiltinRunner` with a `RangeCheck` variant.
    var builtin: BuiltinRunner = .{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) };

    // Initialize a Cairo VM
    var vm = try CairoVM.init(std.testing.allocator, .{});
    // Ensure the Cairo VM is properly deallocated at the end of the test
    defer vm.deinit();

    // Set the current step of the Cairo VM to 8
    // This simulates the current step of the VM for the test scenario.
    vm.current_step = 8;

    // Set segment used sizes to simulate real memory access data
    // Here, the segment used size at index 0 is set to 1, indicating memory usage.
    try vm.segments.segment_used_sizes.put(0, 1);

    // Call the `getUsedPermRangeCheckUnits` function of the `builtin` instance
    // This function retrieves the number of used permanent range check units associated with the built-in runner.
    // In this case, since the built-in runner is a range check operation, the expected number of used units is 8.
    try expectEqual(@as(usize, 8), builtin.getUsedPermRangeCheckUnits(&vm));
}

test "BuiltinRunner:getUsedDilutedCheckUnits with bitwise builtin" {
    // Initialize a `BuiltinRunner` with a `Bitwise` variant.
    var builtin: BuiltinRunner = .{ .Bitwise = .{} };

    // Test the `getUsedDilutedCheckUnits` function with specific parameters.
    try expectEqual(
        @as(usize, 1255),
        try builtin.getUsedDilutedCheckUnits(std.testing.allocator, 270, 7),
    );
}

test "BuiltinRunner:getUsedDilutedCheckUnits with keccak builtin (zero case)" {
    // Initialize a default Keccak instance definition.
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);

    // Initialize a BuiltinRunner union with the KeccakBuiltinRunner variant.
    var builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };

    // Deallocate the BuiltinRunner at the end of the test.
    defer builtin.deinit();

    // Test the `getUsedDilutedCheckUnits` function with specific parameters.
    try expectEqual(
        @as(usize, 0),
        try builtin.getUsedDilutedCheckUnits(std.testing.allocator, 270, 7),
    );
}

test "BuiltinRunner:getUsedDilutedCheckUnits with keccak builtin (non zero case)" {
    // Initialize a default Keccak instance definition
    var keccak_instance_def = try KeccakInstanceDef.initDefault(std.testing.allocator);

    // Initialize a BuiltinRunner union with the KeccakBuiltinRunner variant
    var builtin: BuiltinRunner = .{
        .Keccak = KeccakBuiltinRunner.init(
            std.testing.allocator,
            &keccak_instance_def,
            true,
        ),
    };

    // Ensure the BuiltinRunner instance is properly deallocated at the end of the test
    defer builtin.deinit();

    // Test the `getUsedDilutedCheckUnits` function with specific parameters.
    try expectEqual(
        @as(usize, 32768),
        try builtin.getUsedDilutedCheckUnits(std.testing.allocator, 0, 8),
    );
}

test "BuiltinRunner:getUsedDilutedCheckUnits with elliptic curve operation builtin" {
    // Define the instance definition for the elliptic curve operation
    const instance_def: EcOpInstanceDef = .{ .ratio = 10 };

    // Initialize a BuiltinRunner union with the EcOpBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.init(std.testing.allocator, instance_def, true) };

    // Test the `getUsedDilutedCheckUnits` function with specific parameters.
    try expectEqual(
        @as(usize, 0),
        try builtin.getUsedDilutedCheckUnits(std.testing.allocator, 270, 7),
    );
}

test "BuiltinRunner:getUsedDilutedCheckUnits with hash builtin" {
    // Initialize a BuiltinRunner union with the HashBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .Hash = HashBuiltinRunner.init(std.testing.allocator, 1, true) };

    // Test the `getUsedDilutedCheckUnits` function with specific parameters.
    try expectEqual(
        @as(usize, 0),
        try builtin.getUsedDilutedCheckUnits(std.testing.allocator, 270, 7),
    );
}

test "BuiltinRunner:getUsedDilutedCheckUnits with range check builtin" {
    // Initialize a BuiltinRunner union with the RangeCheckBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .RangeCheck = RangeCheckBuiltinRunner.init(8, 8, true) };

    // Test the `getUsedDilutedCheckUnits` function with specific parameters.
    try expectEqual(
        @as(usize, 0),
        try builtin.getUsedDilutedCheckUnits(std.testing.allocator, 270, 7),
    );
}

test "BuiltinRunner:getUsedDilutedCheckUnits with output builtin" {
    // Initialize a BuiltinRunner union with the OutputBuiltinRunner variant
    var builtin: BuiltinRunner = .{ .Output = OutputBuiltinRunner.init(std.testing.allocator, true) };

    // Test the `getUsedDilutedCheckUnits` function with specific parameters.
    try expectEqual(
        @as(usize, 0),
        try builtin.getUsedDilutedCheckUnits(std.testing.allocator, 270, 7),
    );
}

test "BuiltinRunner: builtin name function" {
    // Initialize a `BuiltinRunner` with the `Bitwise` variant and test its name.
    var bitwise: BuiltinRunner = .{ .Bitwise = .{} };
    try expectEqualStrings("bitwise_builtin", bitwise.name());

    // Initialize a `BuiltinRunner` with the `Hash` variant and test its name.
    var hash: BuiltinRunner = .{ .Hash = HashBuiltinRunner.init(std.testing.allocator, 1, true) };
    try expectEqualStrings("pedersen_builtin", hash.name());

    // Initialize a `BuiltinRunner` with the `RangeCheck` variant and test its name.
    var range_check: BuiltinRunner = .{ .RangeCheck = .{} };
    try expectEqualStrings("range_check_builtin", range_check.name());

    // Initialize a `BuiltinRunner` with the `EcOp` variant and test its name.
    var ec_op: BuiltinRunner = .{ .EcOp = EcOpBuiltinRunner.initDefault(std.testing.allocator) };
    try expectEqualStrings("ec_op_builtin", ec_op.name());

    // Initialize a `BuiltinRunner` with the `Signature` variant and test its name.
    var ecdsa_instance_def = EcdsaInstanceDef.init(512);
    var ecdsa: BuiltinRunner = .{ .Signature = SignatureBuiltinRunner.init(std.testing.allocator, &ecdsa_instance_def, false) };
    try expectEqualStrings("ecdsa_builtin", ecdsa.name());

    // Initialize a `BuiltinRunner` with the `Output` variant and test its name.
    var output: BuiltinRunner = .{ .Output = OutputBuiltinRunner.initDefault(std.testing.allocator) };
    try expectEqualStrings("output_builtin", output.name());
}
