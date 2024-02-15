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

pub const Hints = std.ArrayList(HintParams);

/// Represents a collection of hints.
///
/// This structure contains a list of `HintParams` and a map of `HintRange` corresponding to a `Relocatable`.
pub const HintsCollection = struct {
    const Self = @This();
    /// List of HintParams.
    hints: Hints,
    /// Map of Relocatable to HintRange.
    hints_ranges: std.HashMap(
        Relocatable,
        HintRange,
        std.hash_map.AutoContext(Relocatable),
        std.hash_map.default_max_load_percentage,
    ),

    /// Initializes a new HintsCollection.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the collection.
    pub fn init(allocator: Allocator, hints: std.AutoHashMap(usize, Hints), program_length: usize, extensive_hints: bool) !Self {
        var max_hint_pc = 0;
        var total_hints_len = 0;
        var it = hints.iterator();
        while (it.next()) |kv| {
            max_hint_pc = std.math.max(max_hint_pc, kv.key_ptr.*);
            total_hints_len += kv.value_ptr.items.len;
        }

        if (max_hint_pc == 0 or total_hints_len == 0) {
            return Self.initDefault(allocator);
        }

        if (max_hint_pc >= program_length) {
            return ProgramError.InvalidHintPc;
        }

        var hints_values = try std.ArrayList(HintParams).initCapacity(allocator, total_hints_len);
        var hints_ranges_non_ext: ?std.ArrayList(std.meta.Tuple(.{ usize, usize })) = null;
        var hints_ranges_ext: ?std.AutoHashMap(Relocatable, std.meta.Tuple(.{ usize, usize })) = null;

        if (extensive_hints) {
            hints_ranges_ext = std.AutoHashMap(Relocatable, std.meta.Tuple(.{ usize, usize })).init(allocator);
        } else {
            hints_ranges_non_ext = std.ArrayList(std.meta.Tuple(.{ usize, usize })).init(allocator);
        }

        it = hints.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.*.items.len > 0) {
                const range = .{ hints_values.items.len, kv.value_ptr.items.len };
                if (extensive_hints) {
                    try hints_ranges_ext.?.put(Relocatable.new(0, kv.key_ptr.*), range);
                    try hints_values.appendSlice(kv.value_ptr.items);
                } else {
                    try hints_ranges_non_ext.?.append(range);
                }
            }
        }

        // return Self {
        //     .hints = hints_values,
        //     .hint_ranges = hint
        // }
    }

    /// Initializes a new default HintsCollection.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the collection.
    pub fn initDefault(allocator: Allocator) Self {
        return .{
            .hints = std.ArrayList(HintParams).init(allocator),
            .hints_ranges = std.AutoHashMap(
                Relocatable,
                HintRange,
            ).init(allocator),
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

        // Iterate over hints_ranges to populate the AutoHashMap.
        var it = self.hints_ranges.iterator();

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
    main: ?usize,
    /// Start of the program (optional, defaults to `null`).
    start: ?usize,
    /// End of the program (optional, defaults to `null`).
    end: ?usize,
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
    pub fn init(allocator: Allocator) Self {
        return .{
            .data = std.ArrayList(MaybeRelocatable).init(allocator),
            .hints_collection = HintsCollection.init(allocator),
            .main = null,
            .start = null,
            .end = null,
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

    /// Initializes a new `Program` instance.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the program.
    ///
    /// # Returns:
    ///   - A new instance of `Program`.
    pub fn initDefault(allocator: Allocator) Self {
        return .{
            .shared_program_data = SharedProgramData.init(allocator),
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
                        Felt252.fromSignedInteger(kv.value_ptr.*.value orelse return ProgramError.ConstWithoutValue),
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
                .offset2 = null,
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

    /// Deinitializes the `Program` instance, freeing allocated memory.
    ///
    /// # Params:
    ///   - `self`: A pointer to the `Program` instance.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.shared_program_data.deinit(allocator);
        self.constants.deinit();
        self.builtins.deinit();
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
            .value = 0,
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
            .value = 0,
        },
    );

    // Try to insert a constant identifier representing ALL_ONES with a large negative value.
    try identifiers.put(
        "starkware.cairo.common.bitwise.ALL_ONES",
        .{
            .type = "const",
            .value = -106710729501573572985208420194530329073740042555888586719234,
        },
    );

    // Try to insert constants representing KECCAK_CAPACITY_IN_WORDS.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_CAPACITY_IN_WORDS",
        .{
            .type = "const",
            .value = 8,
        },
    );

    // Try to insert constants representing KECCAK_FULL_RATE_IN_BYTES.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_BYTES",
        .{
            .type = "const",
            .value = 136,
        },
    );

    // Try to insert constants representing KECCAK_FULL_RATE_IN_WORDS.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_WORDS",
        .{
            .type = "const",
            .value = 17,
        },
    );

    // Try to insert constants representing KECCAK_STATE_SIZE_FELTS.
    try identifiers.put(
        "starkware.cairo.common.cairo_keccak.keccak.KECCAK_STATE_SIZE_FELTS",
        .{
            .type = "const",
            .value = 25,
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
        Felt252.zero(),
        constants.get("starkware.cairo.common.alloc.alloc.SIZEOF_LOCALS").?,
    );

    try expectEqual(
        Felt252.fromSignedInteger(-106710729501573572985208420194530329073740042555888586719234),
        constants.get("starkware.cairo.common.bitwise.ALL_ONES").?,
    );

    try expectEqual(
        Felt252.fromInt(u8, 8),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_CAPACITY_IN_WORDS").?,
    );

    try expectEqual(
        Felt252.fromInt(u8, 136),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_BYTES").?,
    );

    try expectEqual(
        Felt252.fromInt(u8, 17),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_FULL_RATE_IN_WORDS").?,
    );

    try expectEqual(
        Felt252.fromInt(u8, 25),
        constants.get("starkware.cairo.common.cairo_keccak.keccak.KECCAK_STATE_SIZE_FELTS").?,
    );
}
