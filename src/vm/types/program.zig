const std = @import("std");
const Allocator = std.mem.Allocator;

const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const HintParams = @import("./programjson.zig").HintParams;
const Attribute = @import("./programjson.zig").Attribute;
const InstructionLocation = @import("./programjson.zig").InstructionLocation;
const Identifier = @import("./programjson.zig").Identifier;
const BuiltinName = @import("./programjson.zig").BuiltinName;
const ReferenceManager = @import("./programjson.zig").ReferenceManager;
const HintReference = @import("../../hint_processor/hint_processor_def.zig").HintReference;

/// Represents a range of hints corresponding to a PC.
///
/// This structure defines a hint range as a pair of values `(start, length)`.
pub const HintRange = struct {
    /// The starting index of the hint range.
    start: usize,
    /// The length of the hint range.
    length: usize,
};

/// Represents a collection of hints.
///
/// This structure contains a list of `HintParams` and a map of `HintRange` corresponding to a `Relocatable`.
pub const HintsCollection = struct {
    const Self = @This();
    /// List of HintParams.
    hints: std.ArrayList(HintParams),
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
    pub fn init(allocator: Allocator) Self {
        return .{
            .hints = std.ArrayList(HintParams).init(allocator),
            .hints_ranges = std.AutoHashMap(
                Relocatable,
                HintRange,
            ).init(allocator),
        };
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
    instruction_locations: ?std.HashMap(
        usize,
        InstructionLocation,
        std.hash_map.AutoContext(usize),
        std.hash_map.default_max_load_percentage,
    ),
    /// Map of `[]u8` to `Identifier`.
    identifiers: std.HashMap(
        []u8,
        Identifier,
        std.hash_map.AutoContext([]u8),
        std.hash_map.default_max_load_percentage,
    ),
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
    pub fn deinit(self: Self) void {
        self.data.deinit();
        self.hints_collection.deinit();
        self.error_message_attributes.deinit();
        if (self.instruction_locations != null) {
            self.instruction_locations.?.deinit();
        }
        self.identifiers.deinit();
        self.reference_manager.deinit();
    }
};

pub const Program = struct {
    const Self = @This();
    shared_program_data: SharedProgramData,
    constants: std.HashMap(
        []u8,
        Felt252,
        std.hash_map.AutoContext([]u8),
        std.hash_map.default_max_load_percentage,
    ),
    builtins: std.ArrayList(BuiltinName),

    pub fn init(allocator: Allocator) Self {
        return .{
            .shared_program_data = SharedProgramData.init(allocator),
            .constants = std.AutoHashMap(
                []u8,
                Felt252,
            ).init(allocator),
            .builtins = std.ArrayList(BuiltinName).init(allocator),
        };
    }

    pub fn from(
        builtins: std.ArrayList(BuiltinName),
        data: std.ArrayList(MaybeRelocatable),
        main: ?usize,
        hints: std.HashMap(
            usize,
            std.ArrayList(HintParams),
            std.hash_map.AutoContext(usize),
            std.hash_map.default_max_load_percentage,
        ),
        reference_manager: ReferenceManager,
        identifiers: std.HashMap(
            []u8,
            Identifier,
            std.hash_map.AutoContext([]u8),
            std.hash_map.default_max_load_percentage,
        ),
        error_message_attributes: std.ArrayList(Attribute),
        instruction_locations: ?std.HashMap(
            usize,
            InstructionLocation,
            std.hash_map.AutoContext(usize),
            std.hash_map.default_max_load_percentage,
        ),
    ) Self {
        _ = error_message_attributes;
        _ = instruction_locations;
        _ = reference_manager;
        _ = identifiers;
        _ = main;
        _ = hints;

        _ = builtins;
        _ = data;
    }

    pub fn deinit(self: Self) void {
        self.shared_program_data.deinit();
        self.constants.deinit();
        self.builtins.deinit();
    }
};
