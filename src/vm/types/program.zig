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

const FlowTrackingData = struct {
    ap_tracking: ApTracking,
    reference_ids: ?json.ArrayHashMap(usize) = null,
};

const Attribute = struct {
    name: []const u8,
    start_pc: usize,
    end_pc: usize,
    value: []const u8,
    flow_tracking_data: ?FlowTrackingData,
};

const HintParams = struct {
    code: []const u8,
    accessible_scopes: []const []const u8,
    flow_tracking_data: FlowTrackingData,
};

const Instruction = struct {
    end_line: u32,
    end_col: u32,
    input_file: struct {
        filename: []const u8,
    },
    parent_location: ?json.Value = null,
    start_col: u32,
    start_line: u32,
};

const HintLocation = struct {
    location: Instruction,
    n_prefix_newlines: u32,
};

const InstructionLocation = struct {
    accessible_scopes: []const []const u8,
    flow_tracking_data: FlowTrackingData,
    inst: Instruction,
    hints: []const HintLocation,
};

const Reference = struct {
    ap_tracking_data: ApTracking,
    pc: ?usize,
    value: []const u8,
};

const IdentifierMember = struct {
    cairo_type: ?[]const u8 = null,
    offset: ?usize = null,
    value: ?[]const u8 = null,
};

const Identifier = struct {
    pc: ?usize = null,
    type: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    decorators: ?[]const u8 = null,
    value: ?i256 = null,
    size: ?usize = null,
    full_name: ?[]const u8 = null,
    references: ?[]const Reference = null,
    members: ?json.ArrayHashMap(IdentifierMember) = null,
    cairo_type: ?[]const u8 = null,
};

/// Represents shared program data.
pub const SharedProgramData = struct {
    const Self = @This();
    /// List of `MaybeRelocatable` items.
    data: []const []const u8,
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
        self.hints_collection.deinit();
        self.error_message_attributes.deinit();
        if (self.instruction_locations != null) {
            self.instruction_locations.?.deinit();
    }
    
    /// # Arguments
    /// - `allocator`: The allocator for reading the json file and parsing it.
    /// - `filename`: The location of the program json file.
    /// # Returns
    /// - a parsed Program
    /// # Errors
    /// - If loading the file fails.
    /// - If the file has incompatible json with respect to the `Program` struct.
    pub fn parseFromFile(allocator: Allocator, filename: []const u8) !json.Parsed(Program) {
        const file = try std.fs.cwd().openFile(filename, .{});
        const file_size = try file.getEndPos();
        defer file.close();

        const buffer = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(buffer);

        const parsed = try json.parseFromSlice(Program, allocator, buffer, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
        errdefer parsed.deinit();

        return parsed;
    }

    /// Takes the `data` array of a json compilation artifact of a v0 cairo program, which contains an array of hexidecimal strings,
    /// and reads them as an array of `MaybeRelocatable`'s to be read into the vm memory.
    /// # Arguments
    /// - `allocator`: The allocator for reading the json file and parsing it.
    /// - `filename`: The location of the program json file.
    /// # Returns
    /// - An ArrayList of `MaybeRelocatable`'s
    /// # Errors
    /// - If the string in the array is not able to be treated as a hex string to be parsed as an u256
    pub fn readData(self: Self, allocator: Allocator) !std.ArrayList(MaybeRelocatable) {
        var parsed_data = std.ArrayList(MaybeRelocatable).init(allocator);
        errdefer parsed_data.deinit();

        for (self.data) |instruction| {
            const parsed_hex = try std.fmt.parseInt(u256, instruction[2..], 16);
            try parsed_data.append(MaybeRelocatable.fromU256(parsed_hex));
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
