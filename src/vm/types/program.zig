const std = @import("std");
const Allocator = std.mem.Allocator;

const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const HintParams = @import("./programjson.zig").HintParams;
const Attribute = @import("./programjson.zig").Attribute;
const Instruction = @import("./programjson.zig").Instruction;
const InstructionLocation = @import("./programjson.zig").InstructionLocation;
const Identifier = @import("./programjson.zig").Identifier;
pub const BuiltinName = @import("./programjson.zig").BuiltinName;
const ReferenceManager = @import("./programjson.zig").ReferenceManager;
const OffsetValue = @import("./programjson.zig").OffsetValue;
const Reference = @import("./programjson.zig").Reference;
const HintReference = @import("../../hint_processor/hint_processor_def.zig").HintReference;
const ProgramError = @import("../error.zig").ProgramError;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

/// Represents a range of hints corresponding to a PC.
///
/// This structure defines a hint range as a pair of values `(start, length)`.
pub const HintRange = struct {
    /// The starting index of the hint range.
    start: usize,
    /// The length of the hint range.
    length: usize,
};

pub const HintsRanges = union(enum) {
    const Self = @This();

    Extensive: std.HashMap(
        Relocatable,
        HintRange,
        std.hash_map.AutoContext(Relocatable),
        std.hash_map.default_max_load_percentage,
    ),
    NonExtensive: std.ArrayList(HintRange),

    pub fn init(
        allocator: Allocator,
        extensive_hints: bool,
    ) Self {
        return switch (extensive_hints) {
            true => Self{ .Extensive = std.AutoHashMap(Relocatable, HintRange).init(allocator) },
            false => Self{ .NonExtensive = std.ArrayList(HintRange).init(allocator) },
        };
    }

    pub fn add(self: *Self, offset: usize, range: HintRange) !void {
        return switch (self.*) {
            .Extensive => |*extensive| try extensive.put(Relocatable.init(0, offset), range),
            .NonExtensive => |*non_extensive| try non_extensive.append(range),
        };
    }

    pub fn isExtensive(self: Self) bool {
        return @as(bool, self == Self.Extensive);
    }

    pub fn count(self: *Self) usize {
        return switch (self.*) {
            .Extensive => |*extensive| extensive.count(),
            .NonExtensive => |*non_extensive| non_extensive.items.len,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .Extensive => |*extensive| extensive.deinit(),
            .NonExtensive => |*non_extensive| non_extensive.deinit(),
        }
    }
};

const Hints = std.ArrayList(HintParams);

/// Represents a collection of hints.
///
/// This structure contains a list of `HintParams` and a map of `HintRange` corresponding to a `Relocatable`.
pub const HintsCollection = struct {
    const Self = @This();
    /// List of HintParams.
    hints: Hints,
    /// Map of Relocatable to HintRange.
    hints_ranges: HintsRanges,

    /// Initializes a new HintsCollection with default values.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the collection.
    pub fn init(allocator: Allocator, hints: std.AutoHashMap(usize, []const HintParams), program_length: usize, extensive_hints: bool) !Self {
        var max_hint_pc = @as(usize, @intCast(0));
        var total_hints_len = @as(usize, @intCast(0));
        var it = hints.iterator();
        while (it.next()) |kv| {
            max_hint_pc = @max(max_hint_pc, kv.key_ptr.*);
            total_hints_len += kv.value_ptr.len;
        }

        if (max_hint_pc == 0 or total_hints_len == 0) {
            return Self.initDefault(allocator);
        }

        if (max_hint_pc >= program_length) {
            return ProgramError.InvalidHintPc;
        }

        var hints_values = try std.ArrayList(HintParams).initCapacity(allocator, total_hints_len);
        errdefer hints_values.deinit();

        var hints_ranges = HintsRanges.init(allocator, extensive_hints);

        it = hints.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.*.len > 0) {
                try hints_ranges.add(
                    kv.key_ptr.*,
                    .{ .start = hints_values.items.len, .length = kv.value_ptr.len },
                );
                try hints_values.appendSlice(kv.value_ptr.*);
            }
        }

        return Self{
            .hints = hints_values,
            .hints_ranges = hints_ranges,
        };
    }

    /// Initializes a new default HintsCollection.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the collection.
    pub fn initDefault(allocator: Allocator) Self {
        return .{
            .hints = std.ArrayList(HintParams).init(allocator),
            .hints_ranges = HintsRanges.init(allocator, true),
        };
    }

    /// Converts the HintsCollection into a HashMap for efficient hint retrieval.
    ///
    /// This method iterates over the `hints_ranges` map, extracts hint ranges, and populates
    /// a new `AutoHashMap` with offsets as keys and corresponding `HintParams` slices as values.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the new AutoHashMap.
    ///
    /// # Returns:
    ///   - An AutoHashMap with offsets as keys and corresponding HintParams slices as values.
    pub fn intoHashMap(
        self: *Self,
        allocator: Allocator,
    ) !std.AutoHashMap(usize, []const HintParams) {
        // Initialize a new AutoHashMap.
        var res = std.AutoHashMap(usize, []const HintParams).init(allocator);
        errdefer res.deinit();

        if (!self.hints_ranges.isExtensive()) {
            return ProgramError.NonExtensiveHints;
        }

        // Iterate over hints_ranges to populate the AutoHashMap.
        var it = self.hints_ranges.Extensive.iterator();

        while (it.next()) |kv| {
            // Calculate the end index of the hint slice.
            const end = kv.value_ptr.start + kv.value_ptr.length;

            // Check if the end index is within bounds of hints.items.
            if (end <= self.hints.items.len) {
                // Put the offset and corresponding hint slice into the AutoHashMap.
                try res.put(
                    kv.key_ptr.offset,
                    self.hints.items[kv.value_ptr.start..end],
                );
            }
        }

        return res;
    }

    /// Deinitializes the HintsCollection, freeing allocated memory.
    pub fn deinit(self: *Self) void {
        self.hints.deinit();
        self.hints_ranges.deinit();
    }
};

/// Represents shared program data.
pub const SharedProgramData = struct {
    const Self = @This();
    /// List of `MaybeRelocatable` items.
    data: std.ArrayList(MaybeRelocatable),
    /// Collection of hints.
    hints_collection: HintsCollection,
    /// Program's main entry point (optional, defaults to `null`).
    main: ?usize = null,
    /// Start of the program (optional, defaults to `null`).
    start: ?usize = null,
    /// End of the program (optional, defaults to `null`).
    end: ?usize = null,
    /// List of error message attributes.
    error_message_attributes: std.ArrayList(Attribute),
    /// Map of `usize` to `InstructionLocation`.
    instruction_locations: ?std.StringHashMap(InstructionLocation),
    /// Map of `[]u8` to `Identifier`.
    identifiers: std.StringHashMap(Identifier),
    /// List of `HintReference` items.
    reference_manager: std.ArrayList(HintReference),

    /// Initializes a new `SharedProgramData` instance.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the instance.
    pub fn initDefault(allocator: Allocator) Self {
        return .{
            .data = std.ArrayList(MaybeRelocatable).init(allocator),
            .hints_collection = HintsCollection.initDefault(allocator),
            .error_message_attributes = std.ArrayList(Attribute).init(allocator),
            .instruction_locations = std.AutoHashMap(
                usize,
                InstructionLocation,
            ).init(allocator),
            .identifiers = std.AutoHashMap(
                []u8,
                Identifier,
            ).init(allocator),
            .reference_manager = std.ArrayList(HintReference).init(allocator),
        };
    }

    /// Deinitializes the `SharedProgramData`, freeing allocated memory.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        // Deinitialize shared data.
        self.data.deinit();

        // Deinitialize hints collection.
        self.hints_collection.deinit();

        // Deinitialize error message attributes.
        self.error_message_attributes.deinit();

        // Check and deinitialize instruction locations if they exist.
        if (self.instruction_locations) |*instruction_locations| {
            // Initialize an iterator over instruction locations.
            var it = instruction_locations.iterator();

            // Iterate through each instruction location.
            while (it.next()) |kv| {
                // Check if the parent_location_instruction exists.
                if (instruction_locations.getPtr(kv.key_ptr.*).?.inst.parent_location_instruction) |*p| {
                    // Retrieve and remove the first element of the list.
                    var it_list = p.popFirst();

                    // Iterate through the list and deallocate nodes.
                    while (it_list) |node| : (it_list = p.popFirst()) {
                        allocator.destroy(node);
                    }
                }
            }
            // Deinitialize the instruction_locations hashmap.
            instruction_locations.deinit();
        }

        // Deinitialize identifiers.
        self.identifiers.deinit();

        // Deinitialize reference manager.
        self.reference_manager.deinit();
    }
};

/// Represents a program structure containing shared data, constants, and built-ins.
pub const Program = struct {
    const Self = @This();
    /// Represents shared data within the program.
    shared_program_data: SharedProgramData,
    /// Contains constants mapped to their values.
    constants: std.StringHashMap(Felt252),
    /// Stores the list of built-in names.
    builtins: std.ArrayList(BuiltinName),
    /// Stores a hash map of hint params
    hints: std.AutoHashMap(usize, []const HintParams),

    /// Initializes a new `Program` instance with provided parameters.
    ///
    /// # Parameters
    /// - `allocator`: The allocator used to initialize the program.
    /// - `builtins`: List of built-in names.
    /// - `data`: List of `MaybeRelocatable` items.
    /// - `main`: The main entry point for the program (optional, defaults to `null`).
    /// - `hints`: Map of offsets to `HintParams` lists (unused, included for autofix compatibility).
    /// - `reference_manager`: The `ReferenceManager` instance.
    /// - `identifiers`: Map of identifiers to `Identifier` instances.
    /// - `error_message_attributes`: List of `Attribute` items for error messages.
    /// - `instruction_locations`: Map of `usize` to `InstructionLocation` (optional, defaults to `null`).
    ///
    /// # Returns
    /// A new `Program` instance initialized with the provided parameters.
    pub fn init(
        allocator: Allocator,
        builtins: std.ArrayList(BuiltinName),
        data: std.ArrayList(MaybeRelocatable),
        main: ?usize,
        hints: std.AutoHashMap(usize, []const HintParams),
        reference_manager: ReferenceManager,
        identifiers: std.StringHashMap(Identifier),
        error_message_attributes: std.ArrayList(Attribute),
        instruction_locations: ?std.StringHashMap(InstructionLocation),
    ) !Self {
        return .{
            .shared_program_data = .{
                .data = data,
                .hints_collection = try HintsCollection.init(allocator, hints, data.items.len, true),
                .main = main,
                .error_message_attributes = error_message_attributes,
                .instruction_locations = instruction_locations,
                .identifiers = identifiers,
                .reference_manager = try reference_manager.getReferenceList(allocator),
            },
            .constants = try Self.extractConstants(identifiers, allocator),
            .builtins = builtins,
            .hints = hints,
        };
    }

    /// Initializes a new `Program` instance.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the program.
    ///
    /// # Returns:
    ///   - A new instance of `Program`.
    pub fn initDefault(allocator: Allocator) Self {
        return .{
            .shared_program_data = SharedProgramData.initDefault(allocator),
            .constants = std.StringHashMap(Felt252).init(allocator),
            .builtins = std.ArrayList(BuiltinName).init(allocator),
        };
    }

    /// Extracts constants from a provided `std.StringHashMap(Identifier)` and returns them
    /// as a new `std.StringHashMap(Felt252)` instance.
    ///
    /// # Params:
    ///   - `identifiers`: The map containing identifiers, including constants.
    ///   - `allocator`: The allocator used to initialize the resulting `std.StringHashMap(Felt252)`.
    ///
    /// # Returns:
    ///   - A new `std.StringHashMap(Felt252)` instance containing extracted constants.
    ///   - Returns an error of type `ProgramError` if there's an issue processing constants.
    pub fn extractConstants(
        identifiers: std.StringHashMap(Identifier),
        allocator: Allocator,
    ) !std.StringHashMap(Felt252) {
        // Initialize the resulting map to store constants.
        var constants = std.StringHashMap(Felt252).init(allocator);
        // Deinitialize the map in case of an error.
        errdefer constants.deinit();

        // Initialize an iterator over identifiers.
        var it = identifiers.iterator();

        // Iterate through each identifier.
        while (it.next()) |kv| {
            // Check if the identifier represents a constant.
            if (kv.value_ptr.*.type) |value| {
                // Check if the constant is explicitly marked as "const".
                if (std.mem.eql(u8, value, "const")) {
                    // Try to insert the constant into the result map.
                    try constants.put(
                        kv.key_ptr.*,
                        kv.value_ptr.*.valueFelt orelse return ProgramError.ConstWithoutValue,
                    );
                }
            }
        }

        // Return the successfully extracted constants.
        return constants;
    }

    /// Retrieves a list of references from a given reference manager.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the list.
    ///   - `reference_manager`: A pointer to an array of references.
    ///
    /// # Returns:
    ///   - A list of `HintReference` containing references.
    pub fn getReferenceList(allocator: Allocator, reference_manager: *[]const Reference) !std.ArrayList(HintReference) {
        var res = std.ArrayList(HintReference).init(allocator);
        errdefer res.deinit();

        for (0..reference_manager.len) |i| {
            const ref = reference_manager.*[i];
            try res.append(.{
                .offset1 = .{ .value = @intCast(ref.ap_tracking_data.offset) },
                .dereference = false,
                .ap_tracking_data = ref.ap_tracking_data,
                .cairo_type = "felt",
            });
        }

        return res;
    }

    /// Retrieves the complete hash map of instruction locations stored in the program's shared data.
    ///
    /// # Returns:
    ///   - A `std.StringHashMap(InstructionLocation)` containing all instruction locations.
    pub fn getInstructionLocations(self: *Self) ?std.StringHashMap(InstructionLocation) {
        return self.shared_program_data.instruction_locations;
    }

    /// Retrieves a specific instruction location based on the provided key.
    ///
    /// # Params:
    ///   - `key`: A byte slice representing the key to retrieve the instruction location.
    ///
    /// # Returns:
    ///   - An optional `InstructionLocation` corresponding to the provided key, if found.
    pub fn getInstructionLocation(self: *Self, key: []const u8) ?InstructionLocation {
        return self.shared_program_data.instruction_locations.?.get(key);
    }

    /// Retrieves an identifier from the program's shared data based on the provided key.
    ///
    /// This function looks up the identifier map within the shared program data using the provided key.
    /// If the key is found, the corresponding `Identifier` instance is returned; otherwise, `null` is returned.
    ///
    /// # Params:
    ///   - `key`: A byte slice representing the key to retrieve the identifier.
    ///
    /// # Returns:
    ///   - An optional `Identifier` corresponding to the provided key, if found; otherwise, `null`.
    pub fn getIdentifier(self: *Self, key: []const u8) ?Identifier {
        return self.shared_program_data.identifiers.get(key);
    }

    /// Retrieves an iterator for the identifiers stored in the program's shared data.
    ///
    /// This method returns an iterator for the `std.StringHashMap(Identifier)` containing
    /// identifiers within the shared program data.
    ///
    /// # Returns:
    ///   - An iterator for the identifiers stored in the program's shared data.
    pub fn iteratorIdentifier(self: *Self) std.StringHashMap(Identifier).Iterator {
        return self.shared_program_data.identifiers.iterator();
    }

    /// Retrieves the length of the list of `MaybeRelocatable` items within the shared program data.
    ///
    /// This function returns the number of elements in the list of `MaybeRelocatable` items, providing
    /// information about the amount of shared program data present in the program instance.
    ///
    /// # Params:
    ///   - `self`: A pointer to the `Program` instance.
    ///
    /// # Returns:
    ///   - The number of elements in the list of `MaybeRelocatable` items.
    pub fn dataLen(self: *Self) usize {
        return self.shared_program_data.data.items.len;
    }

    /// Retrieves the number of built-ins in the program.
    ///
    /// This method returns the length of the list of built-in names stored in the program instance.
    ///
    /// # Returns:
    ///   - The number of built-ins in the program.
    pub fn builtinsLen(self: *Self) usize {
        return self.builtins.items.len;
    }

    /// Deinitializes the `Program` instance, freeing allocated memory.
    ///
    /// # Params:
    ///   - `self`: A pointer to the `Program` instance.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.shared_program_data.deinit(allocator);
        self.constants.deinit();
        self.builtins.deinit();
        self.hints.deinit();
    }
};

test "Program: extractConstants should extract the constants from identifiers" {
    // Initialize a map to store identifiers.
    var identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    // Defer deinitialization to ensure cleanup.
    defer identifiers.deinit();

    // Try to insert a function identifier into the map.
    try identifiers.put(
        "__main__.main",
        .{
            .pc = 0,
            .type = "function",
        },
    );

    // Try to insert a constant identifier into the map.
    try identifiers.put(
        "__main__.main.SIZEOF_LOCALS",
        .{
            .type = "const",
            .valueFelt = Felt252.zero(),
        },
    );

    // Try to extract constants from the identifiers using the `extractConstants` function.
    var constants = try Program.extractConstants(identifiers, std.testing.allocator);
    // Defer deinitialization of the constants to ensure cleanup.
    defer constants.deinit();

    // Check if the number of extracted constants is equal to 1.
    try expectEqual(@as(usize, 1), constants.count());

    // Check if the extracted constant value matches the expected value.
    try expectEqual(Felt252.zero(), constants.get("__main__.main.SIZEOF_LOCALS").?);
}

test "Program: extractConstants should extract the constants from identifiers using large values" {
    // Initialize a map to store identifiers.
    var identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    // Defer deinitialization to ensure cleanup.
    defer identifiers.deinit();

    // Try to insert a constant identifier representing the SIZEOF_LOCALS.
    try identifiers.put(
        "starkware.cairo.common.alloc.alloc.SIZEOF_LOCALS",
        .{
            .type = "const",
            .valueFelt = Felt252.zero(),
        },
    );

    // Try to insert a constant identifier representing ALL_ONES with a large negative value.
    try identifiers.put(
        "starkware.cairo.common.bitwise.ALL_ONES",
        .{
            .type = "const",
            .valueFelt = Felt252.fromInt(u256, 106710729501573572985208420194530329073740042555888586719234).neg(),
        },
    );

    // Try to insert constants representing KECCAK_CAPACITY_IN_WORDS.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_CAPACITY_IN_WORDS",
        .{
            .type = "const",
            .valueFelt = Felt252.fromInt(u8, 8),
        },
    );

    // Try to insert constants representing KECCAK_FULL_RATE_IN_BYTES.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_BYTES",
        .{
            .type = "const",
            .valueFelt = Felt252.fromInt(u8, 136),
        },
    );

    // Try to insert constants representing KECCAK_FULL_RATE_IN_WORDS.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_WORDS",
        .{
            .type = "const",
            .valueFelt = Felt252.fromInt(u8, 17),
        },
    );

    // Try to insert constants representing KECCAK_STATE_SIZE_FELTS.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_STATE_SIZE_FELTS",
        .{
            .type = "const",
            .valueFelt = Felt252.fromInt(u8, 25),
        },
    );

    // Try to insert an alias representing Uint256.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.Uint256",
        .{
            .type = "alias",
            .destination = "starkware.cairo.common.uint256.Uint256",
        },
    );

    // Try to extract constants from the identifiers using the `extractConstants` function.
    var constants = try Program.extractConstants(identifiers, std.testing.allocator);
    // Defer deinitialization of the constants to ensure cleanup.
    defer constants.deinit();

    // Check if the number of extracted constants is equal to 6.
    try expectEqual(@as(usize, 6), constants.count());

    // Check if the extracted constant values match the expected values.
    try expectEqual(
        @as(u256, 0),
        constants.get("starkware.cairo.common.alloc.alloc.SIZEOF_LOCALS").?.toInteger(),
    );

    try expectEqual(
        Felt252.fromInt(u256, 106710729501573572985208420194530329073740042555888586719234).neg(),
        constants.get("starkware.cairo.common.bitwise.ALL_ONES").?,
    );

    try expectEqual(
        @as(u256, 8),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_CAPACITY_IN_WORDS").?.toInteger(),
    );

    try expectEqual(
        @as(u256, 136),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_BYTES").?.toInteger(),
    );

    try expectEqual(
        @as(u256, 17),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_WORDS").?.toInteger(),
    );

    try expectEqual(
        @as(u256, 25),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_STATE_SIZE_FELTS").?.toInteger(),
    );
}

test "Program: init function should init a basic program" {
    // Initialize the reference manager, builtins, hints, identifiers, and error message attributes.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a list of MaybeRelocatable items.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1000));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 2000));
    try data.append(MaybeRelocatable.fromInt(u256, 5201798304953696256));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize a Program instance using the init function.
    var program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null,
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null,
    );

    // Defer the deinitialization of the program to free allocated memory after the test case.
    defer program.deinit(std.testing.allocator);

    // Assertions to validate the initialized program state.
    try expectEqual(@as(usize, 0), program.builtins.items.len);
    try expectEqual(@as(usize, 0), program.constants.count());
    try expectEqualSlices(MaybeRelocatable, data.items, program.shared_program_data.data.items);
    try expectEqual(@as(?usize, null), program.shared_program_data.main);
    try expectEqualDeep(identifiers, program.shared_program_data.identifiers);
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.hints_collection.hints.items.len,
    );
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.hints_collection.hints_ranges.count(),
    );
}

test "Program: init function should init a basic program (data length function)" {
    // Initialize the reference manager, builtins, hints, identifiers, and error message attributes.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a list of MaybeRelocatable items.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1000));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 2000));
    try data.append(MaybeRelocatable.fromInt(u256, 5201798304953696256));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize a Program instance using the init function.
    var program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null, // Main entry point (null for this test case).
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null, // Instruction locations (null for this test case).
    );

    // Defer the deinitialization of the program to free allocated memory after the test case.
    defer program.deinit(std.testing.allocator);

    // Ensure that the `dataLen` function returns the expected length of the shared program data.
    try expectEqual(@as(usize, 6), program.dataLen());
}

test "Program: init function should init a program with identifiers" {
    // Initialize the reference manager, builtins, hints, and error message attributes.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a list of MaybeRelocatable items.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1000));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 2000));
    try data.append(MaybeRelocatable.fromInt(u256, 5201798304953696256));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize a StringHashMap for identifiers.
    var identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);

    // Add identifiers to the StringHashMap.
    try identifiers.put(
        "__main__.main",
        .{
            .pc = 0,
            .type = "function",
        },
    );

    try identifiers.put(
        "__main__.main.SIZEOF_LOCALS",
        .{
            .type = "const",
            .valueFelt = Felt252.zero(),
        },
    );

    // Initialize a Program instance using the init function.
    var program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null, // Main entry point (null for this test case).
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null, // Instruction locations (null for this test case).
    );

    // Defer the deinitialization of the program to free allocated memory after the test case.
    defer program.deinit(std.testing.allocator);

    // Assertions to validate the initialized program state.
    try expectEqual(@as(usize, 0), program.builtins.items.len);
    try expectEqualSlices(MaybeRelocatable, data.items, program.shared_program_data.data.items);
    try expectEqual(@as(?usize, null), program.shared_program_data.main);
    try expectEqualDeep(identifiers, program.shared_program_data.identifiers);
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.hints_collection.hints.items.len,
    );
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.hints_collection.hints_ranges.count(),
    );

    // Additional assertions for programs with identifiers.
    try expectEqual(@as(usize, 1), program.constants.count());
    try expectEqual(Felt252.zero(), program.constants.get("__main__.main.SIZEOF_LOCALS").?);
}

test "Program: init function should init a program with identifiers (get identifiers)" {
    // Initialize the reference manager, builtins, hints, and error message attributes.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a list of MaybeRelocatable items.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1000));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 2000));
    try data.append(MaybeRelocatable.fromInt(u256, 5201798304953696256));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize a StringHashMap for identifiers.
    var identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);

    // Add identifiers to the StringHashMap.
    try identifiers.put(
        "__main__.main",
        .{
            .pc = 0,
            .type = "function",
        },
    );

    try identifiers.put(
        "__main__.main.SIZEOF_LOCALS",
        .{
            .type = "const",
            .valueFelt = Felt252.zero(),
        },
    );

    // Initialize a Program instance using the init function.
    var program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null, // Main entry point (null for this test case).
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null, // Instruction locations (null for this test case).
    );

    // Defer the deinitialization of the program to free allocated memory after the test case.
    defer program.deinit(std.testing.allocator);

    // Test: Verify that identifiers added to the program match those in the initial StringHashMap.

    // Expect the identifier "__main__.main" to match between the program and the initial StringHashMap.
    try expectEqual(
        identifiers.get("__main__.main"),
        program.getIdentifier("__main__.main"),
    );

    // Expect the identifier "__main__.main.SIZEOF_LOCALS" to match between the program and the initial StringHashMap.
    try expectEqual(
        identifiers.get("__main__.main.SIZEOF_LOCALS"),
        program.getIdentifier("__main__.main.SIZEOF_LOCALS"),
    );

    // Expect the identifier "missing" to be null in both the program and the initial StringHashMap.
    try expectEqual(
        identifiers.get("missing"),
        program.getIdentifier("missing"),
    );
}

test "Program: iteratorIdentifier should return an iterator over identifiers" {
    // Initialize the reference manager, builtins, hints, and error message attributes.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);

    // Initialize a list of MaybeRelocatable items.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1000));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 2000));
    try data.append(MaybeRelocatable.fromInt(u256, 5201798304953696256));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize a StringHashMap for identifiers.
    var identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);

    // Add identifiers to the StringHashMap.
    try identifiers.put(
        "__main__.main",
        .{
            .pc = 0,
            .type = "function",
        },
    );

    try identifiers.put(
        "__main__.main.SIZEOF_LOCALS",
        .{
            .type = "const",
            .valueFelt = Felt252.zero(),
        },
    );

    // Initialize a Program instance using the init function.
    var program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null, // Main entry point (null for this test case).
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null, // Instruction locations (null for this test case).
    );

    // Defer the deinitialization of the program to free allocated memory after the test case.
    defer program.deinit(std.testing.allocator);

    // Ensure that the iterator returned by program.iteratorIdentifier() is equal to identifiers.iterator().
    try expectEqualDeep(identifiers.iterator(), program.iteratorIdentifier());

    // Initialize iterators for both the StringHashMap and the Program.
    var program_it = program.iteratorIdentifier();
    var it = identifiers.iterator();

    // Ensure that the size of the iterators match.
    try expectEqual(@as(usize, 2), program_it.hm.size);

    // Iterate through both iterators simultaneously and ensure key-value pairs match.
    while (it.next()) |kv| {
        const program_kv = program_it.next().?;
        try expectEqual(kv.key_ptr.*, program_kv.key_ptr.*);
        try expectEqual(kv.value_ptr.*, program_kv.value_ptr.*);
    }
}

test "Program: init function should init a program with builtins" {
    // Initialize the reference manager, hints, error message attributes, and identifiers.
    const reference_manager = ReferenceManager.init(std.testing.allocator);
    const hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    const error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    const identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);

    // Initialize a list of MaybeRelocatable items.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1000));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 2000));
    try data.append(MaybeRelocatable.fromInt(u256, 5201798304953696256));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize a list of builtins.
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    try builtins.append(BuiltinName.range_check);
    try builtins.append(BuiltinName.bitwise);

    // Initialize a Program instance using the init function.
    var program = try Program.init(
        std.testing.allocator,
        builtins,
        data,
        null, // Main entry point (null for this test case).
        hints,
        reference_manager,
        identifiers,
        error_message_attributes,
        null, // Instruction locations (null for this test case).
    );

    // Defer the deinitialization of the program to free allocated memory after the test case.
    defer program.deinit(std.testing.allocator);

    // Assertions to validate the initialized program state.
    try expectEqualSlices(BuiltinName, builtins.items, program.builtins.items);
    try expectEqualSlices(MaybeRelocatable, data.items, program.shared_program_data.data.items);
    try expectEqual(@as(?usize, null), program.shared_program_data.main);
    try expectEqualDeep(identifiers, program.shared_program_data.identifiers);
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.hints_collection.hints.items.len,
    );
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.hints_collection.hints_ranges.count(),
    );
    // Validate that the number of built-ins in the program matches the expected count.
    try expectEqual(
        @as(usize, 2),
        program.builtinsLen(),
    );
}

test "Program: init a new program with invalid identifiers should return an error" {
    // Initialize the reference manager, builtins, hints, and error message attributes.
    var reference_manager = ReferenceManager.init(std.testing.allocator);
    defer reference_manager.deinit();
    var builtins = std.ArrayList(BuiltinName).init(std.testing.allocator);
    defer builtins.deinit();
    var hints = std.AutoHashMap(usize, []const HintParams).init(std.testing.allocator);
    defer hints.deinit();
    var error_message_attributes = std.ArrayList(Attribute).init(std.testing.allocator);
    defer error_message_attributes.deinit();

    // Initialize a list of MaybeRelocatable items.
    var data = std.ArrayList(MaybeRelocatable).init(std.testing.allocator);
    defer data.deinit();

    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 1000));
    try data.append(MaybeRelocatable.fromInt(u256, 5189976364521848832));
    try data.append(MaybeRelocatable.fromInt(u256, 2000));
    try data.append(MaybeRelocatable.fromInt(u256, 5201798304953696256));
    try data.append(MaybeRelocatable.fromInt(u256, 2345108766317314046));

    // Initialize a StringHashMap for identifiers.
    var identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    defer identifiers.deinit();

    // Add identifiers to the StringHashMap.
    try identifiers.put(
        "__main__.main",
        .{
            .pc = 0,
            .type = "function",
        },
    );

    try identifiers.put(
        "__main__.main.SIZEOF_LOCALS",
        .{
            .type = "const",
        },
    );

    try expectError(
        ProgramError.ConstWithoutValue,
        Program.init(
            std.testing.allocator,
            builtins,
            data,
            null, // Main entry point (null for this test case).
            hints,
            reference_manager,
            identifiers,
            error_message_attributes,
            null, // Instruction locations (null for this test case).
        ),
    );
}
