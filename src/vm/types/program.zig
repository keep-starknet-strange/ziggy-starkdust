const std = @import("std");
const Allocator = std.mem.Allocator;

const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const HintParams = @import("./programjson.zig").HintParams;
const Attribute = @import("./programjson.zig").Attribute;
const InstructionLocation = @import("./programjson.zig").InstructionLocation;
const Identifier = @import("./programjson.zig").Identifier;
pub const BuiltinName = @import("./programjson.zig").BuiltinName;
const ReferenceManager = @import("./programjson.zig").ReferenceManager;
const OffsetValue = @import("./programjson.zig").OffsetValue;
const Reference = @import("./programjson.zig").Reference;
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
    pub fn deinit(self: *Self) void {
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
    pub fn init(allocator: Allocator) Self {
        return .{
            .shared_program_data = SharedProgramData.init(allocator),
            .constants = std.StringHashMap(Felt252).init(allocator),
            .builtins = std.ArrayList(BuiltinName).init(allocator),
        };
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

    /// Deinitializes the `Program` instance, freeing allocated memory.
    ///
    /// # Params:
    ///   - `self`: A pointer to the `Program` instance.
    pub fn deinit(self: *Self) void {
        self.shared_program_data.deinit();
        self.constants.deinit();
        self.builtins.deinit();
    }
};
