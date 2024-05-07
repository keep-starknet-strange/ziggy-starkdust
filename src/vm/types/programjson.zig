const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const Relocatable = @import("../memory/relocatable.zig").Relocatable;
const ProgramError = @import("../error.zig").ProgramError;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const Register = @import("../instructions.zig").Register;
const Program = @import("program.zig").Program;
const HintsCollection = @import("program.zig").HintsCollection;
const SharedProgramData = @import("program.zig").SharedProgramData;
const HintReference = @import("../../hint_processor/hint_processor_def.zig").HintReference;
const PRIME_STR = @import("../../math/fields/starknet.zig").PRIME_STR;
const HashMapWithArray = @import("../../hint_processor/hint_utils.zig").HashMapWithArray;

/// Represents a singly linked list structure specialized for storing Instructions.
pub const InstructionLinkedList = std.SinglyLinkedList(Instruction);

/// Enum representing built-in functions within the Cairo VM.
///
/// This enum defines various built-in functions available within the Cairo VM.
pub const BuiltinName = enum {
    /// Represents the output builtin.
    output,
    /// Represents the range check builtin.
    range_check,
    /// Represents the Pedersen builtin.
    pedersen,
    /// Represents the ECDSA builtin.
    ecdsa,
    /// Represents the Keccak builtin.
    keccak,
    /// Represents the bitwise builtin.
    bitwise,
    /// Represents the EC operation builtin.
    ec_op,
    /// Represents the Poseidon builtin.
    poseidon,
    /// Represents the segment arena builtin.
    segment_arena,
};

/// Represents an offset value union with immediate, value, or reference options.
///
/// This union encompasses different types of offset values: Immediate, Value, or Reference.
pub const OffsetValue = union(enum) {
    /// Immediate value within the `OffsetValue` union.
    immediate: Felt252,
    /// Value within the `OffsetValue` union.
    value: i32,
    /// Reference containing a tuple of `Register`, `i32`, and `bool` within the `OffsetValue` union.
    reference: std.meta.Tuple(&.{ Register, i32, bool }),
};

/// Tracks Ap register changes during execution.
///
/// This structure monitors Ap register progress. When an unknown change occurs,
/// the `group` increases by 1, signifying indeterminacy between register states at two locations.
///
/// Within the same `group`, `offset` mirrors Ap register changes, ensuring a consistent
/// difference between two locations.
///
/// Thus, given Ap register state at one point, it's deducible at another point within the same `group`.
pub const ApTracking = struct {
    const Self = @This();
    /// Indicates register state deducibility (increases by 1 after an unknown change).
    group: usize = 0,
    /// Reflects Ap register changes within the same `group`.
    offset: usize = 0,
};

/// Represents tracking data for references considering various program flows.
///
/// This structure manages reference values at a specific program location, considering all
/// possible flows that may reach that point.
const FlowTrackingData = struct {
    /// Tracks Ap register changes during execution.
    ap_tracking: ApTracking,
    /// Holds reference identifiers corresponding to various flows.
    ///
    /// If populated, this field stores reference identifiers related to different program flows.
    /// It defaults to null if no references are present.
    reference_ids: ?json.ArrayHashMap(usize),
};

/// Represents an attribute with associated metadata and tracking data.
///
/// This structure defines an attribute containing information such as its name, start and end
/// program counters (pcs), a value, and optional flow tracking data.
pub const Attribute = struct {
    /// Name of the attribute.
    name: []const u8,
    /// Start program counter indicating the attribute's starting point.
    start_pc: usize,
    /// End program counter indicating the attribute's ending point.
    end_pc: usize,
    /// Value associated with the attribute.
    value: []const u8,
    /// Flow tracking data for the attribute (optional, defaults to null).
    flow_tracking_data: ?FlowTrackingData,
};

/// Represents parameters associated with a hint, including code, accessible scopes, and tracking data.
///
/// This structure defines parameters related to a hint, comprising code details, accessible scopes,
/// and flow tracking data.
pub const HintParams = struct {
    const Self = @This();

    /// Code associated with the hint.
    code: []const u8,
    /// Accessible scopes for the hint.
    accessible_scopes: []const []const u8,
    /// Flow tracking data related to the hint.
    flow_tracking_data: FlowTrackingData,

    pub fn init(code: []const u8, accessible_scopes: []const []const u8, flow_tracking_data: FlowTrackingData) Self {
        return .{
            .code = code,
            .accessible_scopes = accessible_scopes,
            .flow_tracking_data = flow_tracking_data,
        };
    }
};

/// Represents an instruction with associated location details.
///
/// This structure defines an instruction with start and end line/column information,
/// an input file reference, and optional parent location details.
pub const Instruction = struct {
    /// Ending line number of the instruction.
    end_line: u32,
    /// Ending column number of the instruction.
    end_col: u32,
    /// Input file details containing the filename.
    input_file: struct { filename: []const u8 },
    /// Optional parent location details (defaults to null).
    parent_location: ?json.Value = null,
    /// Optional parent location formatted as a nested `Instruction` instance for `Program` purposes (defaults to null).
    parent_location_instruction: ?std.SinglyLinkedList(Instruction) = null,
    /// Starting column number of the instruction.
    start_col: u32,
    /// Starting line number of the instruction.
    start_line: u32,
};

/// Represents a hint location including location details and prefix newline count.
///
/// This structure defines a hint location, incorporating location information
/// and the count of newlines following the "%{" symbol.
pub const HintLocation = struct {
    /// Location details of the hint.
    location: Instruction,
    /// Number of newlines following the "%{" symbol.
    n_prefix_newlines: u32,
};

/// Represents an instruction location with associated details.
///
/// This structure defines an instruction location, including accessible scopes,
/// flow tracking data, the instruction itself, and related hint locations.
pub const InstructionLocation = struct {
    /// Accessible scopes associated with the instruction location.
    accessible_scopes: []const []const u8,
    /// Flow tracking data specific to the instruction location.
    flow_tracking_data: ?FlowTrackingData = null,
    /// The instruction's location details.
    inst: Instruction,
    /// Array of hint locations related to the instruction.
    hints: []const HintLocation,
};

/// Represents a reference to a memory address defined for a specific program location (pc).
///
/// This structure defines a reference tied to a program counter (pc), holding a value
/// and tracking data for register (ap_tracking_data).
///
/// It may have multiple definition sites (locations) and is associated with a code element responsible for its creation.
///
/// For example,
///
/// Defines a reference 'x' to the Ap register tied to the current instruction.
///
/// [ap] = 5, ap++;
///
/// As 'ap' incremented, the reference evaluates to (ap - 1) instead of 'ap'.
///
/// [ap] = [x] * 2, ap++;
///
/// This instruction translates to '[ap] = [ap - 1] * 2, ap++',
/// setting 'ap' to the calculated value of 10.
///
/// ## Warning:
///
/// This type is valid for a program in Json format uniquely
/// (before deserialization of the value which is stored as a string here)
pub const Reference = struct {
    /// Tracking data for the register associated with the reference.
    ap_tracking_data: ApTracking,
    /// Program counter (pc) tied to the reference (optional, defaults to null).
    pc: ?usize,
    /// Value of the reference.
    value: []const u8,
};

/// Represents the structure defining a memory address.
///
/// This structure includes offset values, a dereference flag, and the value type.
pub const ValueAddress = struct {
    /// First offset value associated with the memory address.
    offset1: OffsetValue,
    /// Second offset value associated with the memory address.
    offset2: OffsetValue,
    /// Indicates whether the memory address is dereferenced.
    dereference: bool,
    /// Type of the value stored at the memory address.
    value_type: []const u8,
};

/// Represents a reference to a memory address defined for a specific program location (pc).
///
/// This structure defines a reference tied to a program counter (pc), holding a value
/// and tracking data for register (ap_tracking_data).
///
/// It may have multiple definition sites (locations) and is associated with a code element responsible for its creation.
///
/// For example,
///
/// Defines a reference 'x' to the Ap register tied to the current instruction.
///
/// [ap] = 5, ap++;
///
/// As 'ap' incremented, the reference evaluates to (ap - 1) instead of 'ap'.
///
/// [ap] = [x] * 2, ap++;
///
/// This instruction translates to '[ap] = [ap - 1] * 2, ap++',
/// setting 'ap' to the calculated value of 10.
///
/// Represents a reference after deserialization where `value` is a `ValueAddress` structure
pub const ReferenceProgram = struct {
    /// Tracking data for the register associated with the reference.
    ap_tracking_data: ApTracking,
    /// Program counter (pc) tied to the reference (optional, defaults to null).
    pc: ?usize,
    /// Value/address of the reference.
    value_address: ValueAddress,
};

/// Represents a manager for references to memory addresses defined for specific program locations (pcs).
///
/// This structure maintains a list of references (`references`)
pub const ReferenceManager = struct {
    const Self = @This();

    /// List of references managed by the `ReferenceManager`.
    references: std.ArrayList(ReferenceProgram),

    /// Initializes a new `ReferenceManager` instance.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the instance.
    pub fn init(allocator: Allocator) Self {
        return .{ .references = std.ArrayList(ReferenceProgram).init(allocator) };
    }

    pub fn getReferenceList(self: *const Self, allocator: Allocator) !std.ArrayList(HintReference) {
        var result = std.ArrayList(HintReference).init(allocator);
        errdefer result.deinit();

        for (self.references.items) |ref| {
            const ap_tracking_data = switch (ref.value_address.offset1) {
                .reference => |r| if (r[0] == .AP) ref.ap_tracking_data else null,
                else => switch (ref.value_address.offset2) {
                    .reference => |r| if (r[0] == .AP) ref.ap_tracking_data else null,
                    else => null,
                },
            };
            try result.append(
                .{
                    .offset1 = ref.value_address.offset1,
                    .offset2 = ref.value_address.offset2,
                    .dereference = ref.value_address.dereference,
                    .ap_tracking_data = ap_tracking_data,
                    .cairo_type = ref.value_address.value_type,
                },
            );
        }

        return result;
    }

    /// Deinitializes the `ReferenceManager`, freeing allocated memory.
    pub fn deinit(self: Self) void {
        self.references.deinit();
    }
};

/// Represents an identifier member within a structure.
///
/// This structure defines an identifier member, which may contain a Cairo type,
/// an offset value, and an associated value.
const IdentifierMember = struct {
    /// Optional Cairo type associated with the member (defaults to null).
    cairo_type: ?[]const u8 = null,
    /// Optional offset value (defaults to null).
    offset: ?usize = null,
    /// Optional value associated with the member (defaults to null).
    value: ?[]const u8 = null,
};

/// This structure defines an identifier.
///
/// It encompasses various details such as program counter (pc), type information,
/// decorators, value, size, full name, associated references, members with their details,
/// and Cairo type.
pub const Identifier = struct {
    /// Program counter (pc) tied to the identifier (optional, defaults to null).
    pc: ?usize = null,
    /// Type information associated with the identifier (optional, defaults to null).
    type: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    /// Decorators related to the identifier (optional, defaults to null).
    decorators: ?[]const []const u8 = null,
    /// Value associated with the identifier (optional, defaults to null).
    value: ?i256 = null,
    /// Value as a Felt252 associated with the identifier (optional, defaults to null).
    valueFelt: ?Felt252 = null,
    /// Size information related to the identifier (optional, defaults to null).
    size: ?usize = null,
    /// Full name of the identifier (optional, defaults to null).
    full_name: ?[]const u8 = null,
    /// References linked to the identifier (optional, defaults to null).
    references: ?[]const Reference = null,
    /// Members associated with the identifier (optional, defaults to null).
    members: ?json.ArrayHashMap(IdentifierMember) = null,
    /// Cairo type information for the identifier (optional, defaults to null).
    cairo_type: ?[]const u8 = null,
};

/// Represents debug information associated with a program.
pub const DebugInfo = struct {
    /// File contents associated with debug information.
    file_contents: ?json.ArrayHashMap([]const u8) = null,
    /// Instruction locations linked with debug information.
    instruction_locations: ?json.ArrayHashMap(InstructionLocation) = null,
};

/// Represents a program in JSON format.
pub const ProgramJson = struct {
    const Self = @This();
    /// List of attributes.
    attributes: ?[]Attribute = null,
    /// List of builtins.
    builtins: ?[]const []const u8 = null,
    /// Compiler version information.
    compiler_version: ?[]const u8 = null,
    /// Program data.
    data: ?[]const []const u8 = null,
    /// Debug information.
    debug_info: ?DebugInfo = null,
    /// Hints associated with the program.
    hints: ?json.ArrayHashMap([]const HintParams) = null,
    /// Identifiers within the program.
    identifiers: ?json.ArrayHashMap(Identifier) = null,
    /// Main scope details.
    main_scope: ?[]const u8 = null,
    /// Prime data.
    prime: ?[]const u8 = null,
    /// Reference manager containing references.
    reference_manager: ?struct {
        /// List of references.
        references: ?[]const Reference = null,
    } = null,

    /// Attempts to parse the compilation artifact of a Cairo v0 program from a JSON file.
    ///
    /// This function reads a JSON file containing program information in the Cairo v0 format
    /// and attempts to parse it into a `ProgramJson` struct.
    ///
    /// # Arguments
    /// - `allocator`: The allocator used for reading the JSON file and parsing it.
    /// - `filename`: The location of the program JSON file.
    ///
    /// # Returns
    /// A parsed `ProgramJson` instance if successful.
    ///
    /// # Errors
    /// - If loading the file fails.
    /// - If the file has incompatible JSON structure with respect to the `ProgramJson` struct.
    pub fn parseFromFile(allocator: Allocator, filename: []const u8) !json.Parsed(Self) {
        // Open the file for reading
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        // Read the entire file content into a buffer using the provided allocator
        const buffer = try file.readToEndAlloc(
            allocator,
            1024 * 1024 * 500,
        );
        defer allocator.free(buffer);

        // Parse the JSON content from the buffer into a `ProgramJson` struct
        return try parseFromString(allocator, buffer);
    }

    /// Parses a JSON string buffer into a `ProgramJson` instance.
    ///
    /// This function takes a JSON string buffer and attempts to parse it into a `ProgramJson` struct.
    ///
    /// # Arguments
    /// - `allocator`: The allocator used for parsing the JSON string buffer.
    /// - `buffer`: The JSON string buffer containing the program information.
    ///
    /// # Returns
    /// A parsed `ProgramJson` instance if successful.
    ///
    /// # Errors
    /// - If parsing the JSON string buffer fails.
    /// - If there are unknown fields in the JSON, unless the 'ignore_unknown_fields' flag is set to true.
    pub fn parseFromString(allocator: Allocator, buffer: []const u8) !json.Parsed(Self) {
        // Parse the JSON string buffer into a `ProgramJson` struct
        const parsed = try json.parseFromSlice(
            Self,
            allocator,
            buffer,
            .{
                // Always allocate memory during parsing
                .allocate = .alloc_always,
                // Ignore unknown fields while parsing
                .ignore_unknown_fields = true,
            },
        );
        errdefer parsed.deinit();

        // Return the parsed `ProgramJson` instance
        return parsed;
    }

    /// Parses a compilation artifact of a Cairo v0 program in JSON format.
    ///
    /// This function extracts relevant information from the provided JSON structure
    /// representing a Cairo v0 program compilation artifact. It constructs a `Program`
    /// instance encapsulating the program's metadata, constants, builtins, and other necessary data.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for memory allocation during parsing.
    /// - `entrypoint`: An optional pointer to the entrypoint identifier's name within the program.
    ///
    /// # Returns
    /// - On success: A parsed `Program` instance.
    /// - On failure: An appropriate `ProgramError` indicating the encountered issue.
    ///
    /// # Errors
    /// - If the program's prime data differs from the expected value.
    /// - If the specified entrypoint identifier is not found.
    /// - If constants within the program lack associated values.
    ///
    /// # Remarks
    /// This function is responsible for converting a JSON representation of a Cairo v0 program
    /// into an internal `Program` structure, enabling subsequent processing and execution.
    ///
    /// The process involves extracting various program elements, including entrypoints, constants,
    /// error messages, instruction locations, and identifiers with associated metadata.
    ///
    /// To use this function effectively, ensure correct and compatible JSON data representing a Cairo v0 program.
    pub fn parseProgramJson(self: *Self, allocator: Allocator, entrypoint: ?*[]const u8, extensive_hints: bool) !Program {
        // Check if the prime string matches the expected value.
        if (!std.mem.eql(u8, PRIME_STR, self.prime.?))
            return ProgramError.PrimeDiffers;

        // Obtain the entrypoint's program counter.
        const entrypoint_pc = try self.getEntrypointPc(allocator, entrypoint);

        // Defer freeing the memory allocated for the entrypoint key.
        if (entrypoint_pc[0]) |*e| {
            defer allocator.free(e.*);
        }

        const hints_collection = try self.getHintsCollections(allocator, extensive_hints);

        // Construct and return a `Program` instance.
        return .{
            .shared_program_data = .{
                .data = try self.readData(allocator),
                .hints_collection = hints_collection,
                .main = entrypoint_pc[1],
                .start = self.getStartPc(),
                .end = self.getEndPc(),
                .error_message_attributes = try self.getErrorMessageAttributes(allocator),
                .instruction_locations = try self.getInstructionLocations(allocator),
                .identifiers = try self.getIdentifiers(allocator),
                .reference_manager = try Program.getReferenceList(
                    allocator,
                    self.reference_manager.?.references.?,
                ),
            },

            .constants = try self.getConstants(allocator),
            .builtins = try self.getBuiltins(allocator),
        };
    }

    /// Takes the `data` array of a json compilation artifact of a v0 cairo program, which contains an array of hexidecimal strings, and reads them as an array of `MaybeRelocatable`'s to be read into the vm memory.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for reading the json file and parsing it.
    /// - `filename`: The location of the program json file.
    ///
    /// # Returns
    /// - An ArrayList of `MaybeRelocatable`'s
    ///
    /// # Errors
    /// - If the string in the array is not able to be treated as a hex string to be parsed as an u256
    pub fn readData(self: Self, allocator: Allocator) !std.ArrayList(MaybeRelocatable) {
        var parsed_data = try std.ArrayList(MaybeRelocatable).initCapacity(allocator, self.data.?.len);
        errdefer parsed_data.deinit();

        for (self.data.?) |instruction| {
            try parsed_data.append(MaybeRelocatable.fromInt(u256, try std.fmt.parseInt(
                u256,
                instruction[2..],
                16,
            )));
        }
        return parsed_data;
    }

    /// Extracts built-in names from a Cairo v0 program's attributes and populates an `ArrayList` with `BuiltinName` instances.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for managing memory during extraction.
    ///
    /// # Returns
    /// An `ArrayList` containing `BuiltinName` instances extracted from the program's attributes.
    ///
    /// # Errors
    /// - If a built-in name is not found in the provided layout.
    pub fn getBuiltins(self: *Self, allocator: Allocator) !std.ArrayList(BuiltinName) {
        // Initialize an array list for storing built-in names.
        var builtins = std.ArrayList(BuiltinName).init(allocator);
        // Deinitialize the array list in case of errors.
        errdefer builtins.deinit();

        // Collects built-in names and adds them to the builtins list.
        if (self.builtins) |builtins_name|
            for (builtins_name) |builtin_name|
                // Convert the string to the corresponding BuiltinName enum value and append it.
                try builtins.append(std.meta.stringToEnum(
                    BuiltinName,
                    builtin_name,
                ) orelse
                    return ProgramError.UnsupportedBuiltin);

        // Return the populated array list of built-in names.
        return builtins;
    }

    /// Retrieves the constants defined within a Cairo v0 program by extracting them from the identifiers and their associated values.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for managing memory during extraction.
    ///
    /// # Returns
    /// A `StringHashMap` containing `Felt252` values associated with their respective identifier keys representing constants within the program.
    ///
    /// # Errors
    /// - If a constant is found without an associated value.
    pub fn getConstants(self: *Self, allocator: Allocator) !std.StringHashMap(Felt252) {
        // Initialize a hashmap to store constants.
        var constants = std.StringHashMap(Felt252).init(allocator);
        // Deinitialize the hashmap in case of errors.
        errdefer constants.deinit();

        // Iterate over identifiers to populate the constants hashmap.
        for (self.identifiers.?.map.keys(), self.identifiers.?.map.values()) |key, value| {
            // Check if the identifier represents a constant.
            if (value.type) |t| {
                if (std.mem.eql(u8, t, "const")) {
                    // Attempt to add the constant to the hashmap.
                    try constants.put(
                        key,
                        // Convert the value to Felt252 and add it to the hashmap.
                        if (value.value) |v|
                            if (v < 0)
                                Felt252.fromInt(u256, @intCast(-v)).neg()
                            else
                                Felt252.fromInt(u256, @intCast(v))
                        else
                            return ProgramError.ConstWithoutValue,
                    );
                }
            }
        }

        // Return the populated constants hashmap.
        return constants;
    }

    /// Collects error message attributes from the program's attributes.
    ///
    /// This function iterates through the provided attributes of a Cairo v0 program
    /// and collects attributes with the name "error_message", adding them to a list
    /// of attributes related to error messages.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for memory allocation during attribute collection.
    ///
    /// # Returns
    /// - An ArrayList of `Attribute` instances related to error messages.
    pub fn getErrorMessageAttributes(self: *Self, allocator: Allocator) !std.ArrayList(Attribute) {
        // Initialize an array list to store error message attributes.
        var error_message_attributes = std.ArrayList(Attribute).init(allocator);
        // Deinitialize the array list in case of errors.
        errdefer error_message_attributes.deinit();

        // Iterate through the attributes and collect those named "error_message".
        for (self.attributes.?) |attribute| {
            // Check if the attribute name matches "error_message".
            if (std.mem.eql(u8, attribute.name, "error_message")) {
                // Append the attribute to the error message attributes list.
                try error_message_attributes.append(attribute);
            }
        }

        // Return the collected error message attributes.
        return error_message_attributes;
    }

    /// Collects identifiers and associated metadata into a hashmap.
    ///
    /// This function iterates through the provided identifiers' map of a Cairo v0 program
    /// and constructs a hashmap containing identifiers as keys and their metadata as values.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for memory allocation during identifier collection.
    ///
    /// # Returns
    /// - A StringHashMap of `Identifier` instances containing program identifiers and metadata.
    pub fn getIdentifiers(self: *Self, allocator: Allocator) !std.StringHashMap(Identifier) {
        // Initialize a StringHashMap to store identifiers and metadata.
        var identifiers = std.StringHashMap(Identifier).init(allocator);
        // Deinitialize the hashmap in case of errors.
        errdefer identifiers.deinit();

        // Iterate through the identifiers and populate the hashmap with metadata.
        for (self.identifiers.?.map.keys(), self.identifiers.?.map.values()) |key, value| {
            var val = value;
            // If the identifier has a numeric value, convert it to Felt252 and update the valueFelt field.
            if (val.value) |v| {
                val.valueFelt = if (v < 0)
                    Felt252.fromInt(u256, @intCast(-v)).neg()
                else
                    Felt252.fromInt(u256, @intCast(v));
            }
            // Put the identifier and its metadata into the hashmap.
            try identifiers.put(key, val);
        }

        // Return the populated hashmap of identifiers.
        return identifiers;
    }

    /// Retrieves and organizes debug information related to instruction locations.
    ///
    /// This function extracts and organizes debug information concerning instruction locations
    /// from the provided `debug_info` of a Cairo v0 program compilation artifact.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for memory allocation during instruction location retrieval.
    ///
    /// # Returns
    /// - A StringHashMap containing debug information related to instruction locations.
    ///   Keys represent the location identifier, and values encapsulate instruction location metadata.
    pub fn getInstructionLocations(self: *Self, allocator: Allocator) !std.StringHashMap(InstructionLocation) {
        // Initialize a StringHashMap to store instruction locations and their metadata.
        var instruction_locations = std.StringHashMap(InstructionLocation).init(allocator);
        // Deinitialize the hashmap in case of errors.
        errdefer instruction_locations.deinit();

        // Check if debug information related to instruction locations exists.
        if (self.debug_info.?.instruction_locations) |il| {
            // Iterate through the keys and values in the instruction locations map.
            for (il.map.keys(), il.map.values()) |key, *value| {
                // Initialize a linked list and a pointer to the parent location.
                var list = InstructionLinkedList{};
                var parent_location = value.inst.parent_location;

                // Process each parent location in the instruction.
                while (parent_location) |p| {
                    // Retrieve content for the current parent location.
                    const p_content = p.array.items[0].object;

                    // Create and allocate a new Node for the linked list.
                    const instruction = try allocator.create(InstructionLinkedList.Node);
                    errdefer allocator.destroy(instruction);

                    // Assign values to the Node based on the parent location content.
                    instruction.* = InstructionLinkedList.Node{ .data = .{
                        .end_col = @intCast(p_content.get("end_col").?.integer),
                        .end_line = @intCast(p_content.get("end_line").?.integer),
                        .input_file = .{
                            .filename = p_content.get("input_file").?.object.get("filename").?.string,
                        },
                        .start_col = @intCast(p_content.get("start_col").?.integer),
                        .start_line = @intCast(p_content.get("start_line").?.integer),
                    } };

                    // Insert the newly created Node into the linked list.
                    if (list.len() == 0) {
                        list.prepend(instruction);
                    } else {
                        InstructionLinkedList.Node.findLast(list.first.?).insertAfter(instruction);
                    }
                    parent_location = p_content.get("parent_location");
                }

                // Set the parent location instruction list in the value struct.
                if (list.len() > 0)
                    value.inst.parent_location_instruction = list;

                // Put each key-value pair into the instruction_locations hashmap.
                try instruction_locations.put(key, value.*);
            }
        }

        // Return the populated hashmap of instruction locations.
        return instruction_locations;
    }

    /// Retrieves the program counter (pc) for the start of the main function.
    ///
    /// This function retrieves the program counter (pc) indicating the start of the main function
    /// within the Cairo v0 program's identifiers. If the program counter is found, it is returned;
    /// otherwise, it returns null.
    ///
    /// # Returns
    /// - If found: The program counter (pc) for the start of the main function.
    /// - If not found: Null.
    pub fn getStartPc(self: *Self) ?usize {
        // Check if the identifier for the start of the main function exists in identifiers.
        if (self.identifiers.?.map.get("__main__.__start__")) |identifier| {
            // Return the program counter (pc) for the start of the main function.
            return identifier.pc;
        }
        // Return null if the start of the main function identifier is not found.
        return null;
    }

    /// Retrieves the program counter (pc) for the end of the main function.
    ///
    /// This function retrieves the program counter (pc) indicating the end of the main function
    /// within the Cairo v0 program's identifiers. If the program counter is found, it is returned;
    /// otherwise, it returns null.
    ///
    /// # Returns
    /// - If found: The program counter (pc) for the end of the main function.
    /// - If not found: Null.
    pub fn getEndPc(self: *Self) ?usize {
        // Check if the identifier for the end of the main function exists in identifiers.
        if (self.identifiers.?.map.get("__main__.__end__")) |identifier| {
            // Return the program counter (pc) for the end of the main function.
            return identifier.pc;
        }
        // Return null if the end of the main function identifier is not found.
        return null;
    }

    /// Retrieves the program counter (PC) associated with the specified entrypoint identifier.
    ///
    /// This function aims to obtain the program counter linked to the provided entrypoint identifier.
    /// If the identifier exists in the program's identifiers map, it returns a tuple containing the entrypoint
    /// identifier's concatenated key and its associated program counter (PC). If not found, it returns a tuple
    /// with null values.
    ///
    /// # Arguments
    /// - `self`: A reference to the program instance.
    /// - `allocator`: The allocator for managing memory.
    /// - `entrypoint`: An optional pointer to the entrypoint identifier's name within the program.
    ///
    /// # Returns
    /// A tuple containing the entrypoint identifier's concatenated key and its corresponding program counter (PC)
    /// if the identifier exists. If not found, it returns a tuple with null values.
    ///
    /// # Errors
    /// - If the specified entrypoint identifier is not found within the program.
    pub fn getEntrypointPc(
        self: *Self,
        allocator: Allocator,
        entrypoint: ?*[]const u8,
    ) !std.meta.Tuple(&.{ ?[]u8, ?usize }) {
        // Check if an entrypoint is provided.
        return if (entrypoint) |e| blk: {
            // Concatenate the entrypoint identifier with "__main__."
            const key = try std.mem.concat(
                allocator,
                u8,
                &[_][]const u8{ "__main__.", e.* },
            );
            // Defer freeing the memory allocated for the key.
            errdefer allocator.free(key);

            // Check if the entrypoint identifier exists in the identifiers map.
            if (self.identifiers.?.map.get(key)) |entrypoint_identifier| {
                // Return the key and its associated program counter.
                break :blk .{ key, entrypoint_identifier.pc };
            } else {
                // Return an error if the entrypoint identifier is not found.
                return ProgramError.EntrypointNotFound;
            }
        } else .{ null, null }; // Return null values if no entrypoint is provided.
    }

    pub fn transformParentLocation(parent_location: std.json.ObjectMap) Instruction {
        return .{
            .end_col = @intCast(parent_location.get("end_col").?.integer),
            .end_line = @intCast(parent_location.get("end_line").?.integer),
            .input_file = .{
                .filename = parent_location.get("input_file").?.object.get("filename").?.string,
            },
            .start_col = @intCast(parent_location.get("start_col").?.integer),
            .start_line = @intCast(parent_location.get("start_line").?.integer),
        };
    }

    /// Retrieves the hints from the program's `hints` map and organizes them into a `HintsCollection`.
    ///
    /// This function iterates over the hints map, extracts information about the maximum hint PC
    /// and the total length of hints. It then initializes a new `HintsCollection` and populates it
    /// with ranges and hint values from the map. The resulting `HintsCollection` is returned.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the `HintsCollection`.
    ///
    /// # Returns:
    ///   - A `HintsCollection` containing organized hint information.
    pub fn getHintsCollections(self: *Self, allocator: Allocator, extensive_hints: bool) !HintsCollection {
        // Initialize variables to track maximum hint PC and total length of hints.
        var max_hint_pc: ?usize = null;
        var full_len: ?usize = null;

        // Iterate over the hints map to calculate max_hint_pc and full_len.
        if (self.hints) |hints| {
            var it = hints.map.iterator();

            while (it.next()) |entry| {
                max_hint_pc = @max(
                    max_hint_pc orelse 0,
                    try std.fmt.parseInt(usize, entry.key_ptr.*, 10),
                );
                full_len = full_len orelse 0 + entry.value_ptr.len;
            }
        }

        // Check if there are valid hints to collect.
        if (max_hint_pc != null and full_len != null) {
            // Check for invalid max_hint_pc value.
            if (max_hint_pc.? >= self.data.?.len) return ProgramError.InvalidHintPc;

            // Initialize a new HintsCollection.

            var hints_collection = try HintsCollection.initDefault(allocator, extensive_hints);
            errdefer hints_collection.deinit();

            if (!extensive_hints) {
                try hints_collection.hints_ranges.NonExtensive.appendNTimes(null, max_hint_pc.? + 1);
            }

            // Iterate over the hints map to populate the HintsCollection.
            if (self.hints) |hints| {
                var it = hints.map.iterator();

                while (it.next()) |entry| {
                    // Check for empty vector in the hints map.
                    if (entry.value_ptr.len <= 0) return ProgramError.EmptyVecAlreadyFiltered;
                    const pc = try std.fmt.parseInt(u64, entry.key_ptr.*, 10);

                    if (extensive_hints) {
                        // Populate hints_ranges and hints in the HintsCollection.
                        try hints_collection.hints_ranges.Extensive.put(
                            Relocatable.init(
                                0,
                                pc,
                            ),
                            .{
                                .start = hints_collection.hints.items.len,
                                .length = entry.value_ptr.len,
                            },
                        );
                    } else {
                        hints_collection.hints_ranges.NonExtensive.items[pc] = .{
                            .start = hints_collection.hints.items.len,
                            .length = entry.value_ptr.len,
                        };
                    }

                    try hints_collection.hints.appendSlice(entry.value_ptr.*);
                }
            }

            return hints_collection;
        }

        // Return an empty HintsCollection if there are no valid hints.
        return HintsCollection.initDefault(allocator, extensive_hints);
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualDeep = std.testing.expectEqualDeep;

test "ProgramJson cannot be initialized from nonexistent json file" {
    try expectError(
        error.FileNotFound,
        ProgramJson.parseFromFile(
            std.testing.allocator,
            "nonexistent.json",
        ),
    );
}

test "ProgramJson can be initialized from json file with correct program data" {
    // Allocate memory for testing purposes using std.testing.allocator.
    const allocator = std.testing.allocator;

    // Define a buffer to hold the absolute path of the JSON file.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Parse the ProgramJson from the JSON file for testing.
    var parsed_program = try ProgramJson.parseFromFile(
        allocator,
        try std.posix.realpath("cairo_programs/fibonacci.json", &buffer),
    );
    defer parsed_program.deinit(); // Ensure deallocation after the test.

    // Read the data from the parsed ProgramJson.
    const data = try parsed_program.value.readData(allocator);
    // Deallocate the data after the test.
    defer data.deinit();

    // Define expected data obtained from the JSON file.
    const expected_data: []const []const u8 = &[_][]const u8{
        "0x480680017fff8000",
        "0x1",
        "0x480680017fff8000",
        "0x1",
        "0x480680017fff8000",
        "0xa",
        "0x1104800180018000",
        "0x5",
        "0x400680017fff7fff",
        "0x90",
        "0x208b7fff7fff7ffe",
        "0x20780017fff7ffd",
        "0x5",
        "0x480a7ffc7fff8000",
        "0x480a7ffc7fff8000",
        "0x208b7fff7fff7ffe",
        "0x482a7ffc7ffb8000",
        "0x480a7ffc7fff8000",
        "0x48127ffe7fff8000",
        "0x482680017ffd8000",
        "0x800000000000011000000000000000000000000000000000000000000000000",
        "0x1104800180018000",
        "0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffff7",
        "0x208b7fff7fff7ffe",
    };

    // Ensure the length of expected data matches the parsed data.
    try expectEqual(expected_data.len, data.items.len);

    // Iterate through each item in the parsed data.
    for (0..expected_data.len) |idx| {
        // Initialize a list to store hexadecimal representations.
        var hex_list = std.ArrayList(u8).init(allocator);
        // Deallocate after each iteration.
        defer hex_list.deinit();

        // Convert the felt integer to a hexadecimal representation.
        try std.fmt.format(
            hex_list.writer(),
            "0x{x}",
            .{data.items[idx].felt.toInteger()},
        );

        // Ensure the generated hexadecimal string matches the expected value.
        try expectEqualStrings(expected_data[idx], hex_list.items);
    }
}

test "ProgramJson: parseFromFile should return a parsed ProgramJson instance from a valid JSON A" {
    // Buffer to store the path of the JSON file
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Attempting to parse a ProgramJson instance from a JSON file
    var parsed_program = try ProgramJson.parseFromFile(
        std.testing.allocator,
        try std.posix.realpath(
            "cairo_programs/manually_compiled/valid_program_a.json",
            &buffer,
        ),
    );
    // Deinitializing parsed_program at the end of the scope
    defer parsed_program.deinit();

    // Expecting equality for a specific string field in the parsed JSON
    try expectEqualStrings(
        "0x800000000000011000000000000000000000000000000000000000000000001",
        parsed_program.value.prime.?,
    );

    // Expecting that a certain field in the parsed JSON has an empty array or is not present
    try expect(parsed_program.value.builtins.?.len == 0);

    // Expecting that a certain field in the parsed JSON has an array of length 6
    try expect(parsed_program.value.data.?.len == 6);

    // Expecting equality for a specific numeric value extracted from identifiers in the parsed JSON
    try expectEqual(
        @as(usize, 0),
        parsed_program.value.identifiers.?.map.get("__main__.main").?.pc,
    );
}

test "ProgramJson: parseFromFile should return a parsed ProgramJson instance from a valid JSON B" {
    // Buffer to store the path of the JSON file
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Attempting to parse a ProgramJson instance from a JSON file
    var parsed_program = try ProgramJson.parseFromFile(
        std.testing.allocator,
        try std.posix.realpath(
            "cairo_programs/manually_compiled/valid_program_b.json",
            &buffer,
        ),
    );
    // Deinitializing parsed_program at the end of the scope
    defer parsed_program.deinit();

    // Expecting equality for a specific string field in the parsed JSON
    try expectEqualStrings(
        "0x800000000000011000000000000000000000000000000000000000000000001",
        parsed_program.value.prime.?,
    );

    // Expected builtins to compare against the parsed JSON builtins
    const expected_builtins = [_][]const u8{
        "output",
        "range_check",
    };

    // Loop through parsed JSON builtins and compare with expected builtins
    for (parsed_program.value.builtins.?, 0..) |builtin, i| {
        try expectEqualStrings(expected_builtins[i], builtin);
    }

    // Expecting that a certain field in the parsed JSON has an array of length 24
    try expect(parsed_program.value.data.?.len == 24);

    // Expecting equality for a specific numeric value extracted from identifiers in the parsed JSON
    try expectEqual(
        @as(usize, 13),
        parsed_program.value.identifiers.?.map.get("__main__.main").?.pc,
    );
}

test "ProgramJson: parseFromString should return a parsed ProgramJson instance from string" {
    const valid_json =
        \\  {
        \\     "prime": "0x800000000000011000000000000000000000000000000000000000000000001",
        \\     "attributes": [],
        \\    "debug_info": {
        \\        "instruction_locations": {}
        \\    },
        \\    "builtins": [],
        \\ "data": [
        \\    "0x480680017fff8000",
        \\    "0x3e8",
        \\    "0x480680017fff8000",
        \\    "0x7d0",
        \\    "0x48307fff7ffe8000",
        \\    "0x208b7fff7fff7ffe"
        \\ ],
        \\ "identifiers": {
        \\    "__main__.main": {
        \\        "decorators": [],
        \\        "pc": 0,
        \\        "type": "function"
        \\    },
        \\    "__main__.main.Args": {
        \\        "full_name": "__main__.main.Args",
        \\        "members": {},
        \\        "size": 0,
        \\        "type": "struct"
        \\    },
        \\    "__main__.main.ImplicitArgs": {
        \\        "full_name": "__main__.main.ImplicitArgs",
        \\        "members": {},
        \\        "size": 0,
        \\        "type": "struct"
        \\    }
        \\ },
        \\ "hints": {
        \\     "0": [
        \\        {
        \\            "accessible_scopes": [
        \\                "starkware.cairo.common.alloc",
        \\               "starkware.cairo.common.alloc.alloc"
        \\           ],
        \\         "code": "memory[ap] = segments.add()",
        \\       "flow_tracking_data": {
        \\          "ap_tracking": {
        \\"group": 0,
        \\ "offset": 0
        \\ },
        \\ "reference_ids": {
        \\     "starkware.cairo.common.math.split_felt.high": 0,
        \\    "starkware.cairo.common.math.split_felt.low": 14,
        \\      "starkware.cairo.common.math.split_felt.range_check_ptr": 16,
        \\       "starkware.cairo.common.math.split_felt.value": 12
        \\      }
        \\     }
        \\   }
        \\    ]
        \\   },
        \\    "reference_manager": {
        \\       "references": [
        \\            {
        \\                "ap_tracking_data": {
        \\                     "group": 0,
        \\                    "offset": 0
        \\               },
        \\               "pc": 0,
        \\               "value": "[cast(fp + (-4), felt*)]"
        \\           },
        \\          {
        \\               "ap_tracking_data": {
        \\                    "group": 0,
        \\                    "offset": 0
        \\               },
        \\                "pc": 0,
        \\                "value": "[cast(fp + (-3), felt*)]"
        \\            },
        \\           {
        \\              "ap_tracking_data": {
        \\                  "group": 0,
        \\                    "offset": 0
        \\              },
        \\               "pc": 0,
        \\             "value": "cast([fp + (-3)] + 2, felt)"
        \\           },
        \\           {
        \\               "ap_tracking_data": {
        \\                   "group": 0,
        \\                    "offset": 0
        \\                },
        \\                "pc": 0,
        \\                 "value": "[cast(fp, felt**)]"
        \\             }
        \\         ]
        \\      }
        \\  }
    ;

    // Parsing the JSON string into a `ProgramJson` instance
    var parsed_program = try ProgramJson.parseFromString(std.testing.allocator, valid_json);
    defer parsed_program.deinit();

    // Expectation: prime value matches
    try expectEqualStrings(
        "0x800000000000011000000000000000000000000000000000000000000000001",
        parsed_program.value.prime.?,
    );

    // Expectation: length of builtins is 0
    try expect(parsed_program.value.builtins.?.len == 0);

    // Expectation: `pc` value for "__main__.main" identifier is 0
    try expect(parsed_program.value.identifiers.?.map.get("__main__.main").?.pc == 0);

    // Expectation: Data array matches the expected values
    const expected_data = [_][]const u8{
        "0x480680017fff8000",
        "0x3e8",
        "0x480680017fff8000",
        "0x7d0",
        "0x48307fff7ffe8000",
        "0x208b7fff7fff7ffe",
    };
    for (parsed_program.value.data.?, 0..) |data, i| {
        try expectEqualStrings(expected_data[i], data);
    }

    // Read the data from the parsed ProgramJson.
    const data_vec = try parsed_program.value.readData(std.testing.allocator);
    // Deallocate the data after the test.
    defer data_vec.deinit();

    // Initialize an array list to hold the expected data using MaybeRelocatable type.
    const expected_data_vec = [_]MaybeRelocatable{
        MaybeRelocatable.fromInt(u256, 5189976364521848832),
        MaybeRelocatable.fromInt(u256, 1000),
        MaybeRelocatable.fromInt(u256, 5189976364521848832),
        MaybeRelocatable.fromInt(u256, 2000),
        MaybeRelocatable.fromInt(u256, 5201798304953696256),
        MaybeRelocatable.fromInt(u256, 2345108766317314046),
    };

    // Compare the items in the expected and parsed data arrays.
    try expectEqualSlices(MaybeRelocatable, &expected_data_vec, data_vec.items);

    // Expectation: Code in hints matches an expected string
    try expectEqualStrings(
        "memory[ap] = segments.add()",
        parsed_program.value.hints.?.map.get("0").?[0].code,
    );

    // Defining an array of expected accessible scopes
    const expected_hint_accessible_scope = [_][]const u8{
        "starkware.cairo.common.alloc",
        "starkware.cairo.common.alloc.alloc",
    };

    // Looping through the accessible scopes extracted from the parsed JSON and comparing them with expected values
    for (parsed_program.value.hints.?.map.get("0").?[0].accessible_scopes, 0..) |accessible_scope, i| {
        try expectEqualStrings(expected_hint_accessible_scope[i], accessible_scope);
    }

    // Expecting equality for ApTracking's ap_tracking field extracted from parsed JSON
    try expectEqual(
        ApTracking{ .group = 0, .offset = 0 },
        parsed_program.value.hints.?.map.get("0").?[0].flow_tracking_data.ap_tracking,
    );

    // Expecting equality for specific numeric values from reference_ids in flow_tracking_data
    try expectEqual(
        @as(usize, 0),
        parsed_program.value.hints.?.map.get("0").?[0].flow_tracking_data.reference_ids.?.map.get("starkware.cairo.common.math.split_felt.high"),
    );
    try expectEqual(
        @as(usize, 14),
        parsed_program.value.hints.?.map.get("0").?[0].flow_tracking_data.reference_ids.?.map.get("starkware.cairo.common.math.split_felt.low"),
    );
    try expectEqual(
        @as(usize, 16),
        parsed_program.value.hints.?.map.get("0").?[0].flow_tracking_data.reference_ids.?.map.get("starkware.cairo.common.math.split_felt.range_check_ptr"),
    );
    try expectEqual(
        @as(usize, 12),
        parsed_program.value.hints.?.map.get("0").?[0].flow_tracking_data.reference_ids.?.map.get("starkware.cairo.common.math.split_felt.value"),
    );

    // Defining an array of expected Reference values
    const expected_reference_manager = [_]Reference{
        .{ .ap_tracking_data = .{ .group = 0, .offset = 0 }, .pc = 0, .value = "[cast(fp + (-4), felt*)]" },
        .{ .ap_tracking_data = .{ .group = 0, .offset = 0 }, .pc = 0, .value = "[cast(fp + (-3), felt*)]" },
        .{ .ap_tracking_data = .{ .group = 0, .offset = 0 }, .pc = 0, .value = "cast([fp + (-3)] + 2, felt)" },
        .{ .ap_tracking_data = .{ .group = 0, .offset = 0 }, .pc = 0, .value = "[cast(fp, felt**)]" },
    };

    // Looping through the reference manager references extracted from parsed JSON and comparing them with expected values
    for (parsed_program.value.reference_manager.?.references.?, 0..) |ref, i| {
        try expectEqual(expected_reference_manager[i].ap_tracking_data, ref.ap_tracking_data);
        try expectEqual(expected_reference_manager[i].pc, ref.pc);
        try expectEqualStrings(expected_reference_manager[i].value, ref.value);
    }
}

test "ProgramJson: parseProgramJson should parse a Cairo v0 JSON Program and convert it to a Program" {
    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.posix.realpath("cairo_programs/fibonacci.json", &buffer);
    // Parse the JSON file into a `ProgramJson` structure
    var parsed_program = try ProgramJson.parseFromFile(std.testing.allocator, path);
    defer parsed_program.deinit();

    // Specify the entrypoint identifier
    var entrypoint: []const u8 = "main";
    // Parse the program JSON into a `Program` structure
    var program = try parsed_program.value.parseProgramJson(
        std.testing.allocator,
        &entrypoint,
        true,
    );
    defer program.deinit(std.testing.allocator);

    // Test the builtins count
    try expect(program.builtins.items.len == 0);

    // Test the count of constants within the program
    try expectEqual(@as(usize, 2), program.constants.count());

    // Test individual constant values within the program
    try expectEqual(Felt252.zero(), program.constants.get("__main__.fib.SIZEOF_LOCALS").?);
    try expectEqual(Felt252.zero(), program.constants.get("__main__.main.SIZEOF_LOCALS").?);

    // Test hints collection count within shared_program_data
    try expect(program.shared_program_data.hints_collection.hints.items.len == 0);
    // Test hints_ranges count within shared_program_data
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.hints_collection.hints_ranges.count(),
    );

    // Test various attributes and properties within shared_program_data
    try expectEqual(@as(?usize, 0), program.shared_program_data.main);
    try expectEqual(@as(?usize, null), program.shared_program_data.start);
    try expectEqual(@as(?usize, null), program.shared_program_data.end);
    try expect(program.shared_program_data.error_message_attributes.items.len == 0);
    try expectEqual(
        @as(usize, 16),
        program.getInstructionLocations().?.count(),
    );

    // Test a specific instruction location within shared_program_data
    const instruction_location_0 = program.getInstructionLocation("0").?;

    // Define an array containing expected accessible scopes
    const expected_accessible_scopes = [_][]const u8{ "__main__", "__main__.main" };

    // Loop through accessible_scopes and compare with expected values
    for (0..instruction_location_0.accessible_scopes.len) |i| {
        try expectEqualStrings(
            expected_accessible_scopes[i],
            instruction_location_0.accessible_scopes[i],
        );
    }

    // Test ApTracking data within instruction_location_0
    try expectEqual(
        ApTracking{ .group = 0, .offset = 0 },
        instruction_location_0.flow_tracking_data.?.ap_tracking,
    );

    // Test the count of reference_ids within flow_tracking_data
    try expectEqual(
        @as(usize, 0),
        instruction_location_0.flow_tracking_data.?.reference_ids.?.map.count(),
    );

    // Test various properties of the instruction (e.g., start and end positions, parent_location, filename)
    try expect(instruction_location_0.inst.end_line == 3);
    try expect(instruction_location_0.inst.end_col == 29);
    try expect(instruction_location_0.inst.parent_location == null);
    try expect(instruction_location_0.inst.start_col == 28);
    try expect(instruction_location_0.inst.start_line == 3);
    try expectEqualStrings(
        "cairo_programs/fibonacci.cairo",
        instruction_location_0.inst.input_file.filename,
    );

    // Test the count of hints within instruction_location_0
    try expect(instruction_location_0.hints.len == 0);

    // Test the count of identifiers within shared_program_data
    try expectEqual(@as(usize, 17), program.shared_program_data.identifiers.count());

    // Access a specific identifier and test its properties
    const identifier_zero = program.shared_program_data.identifiers.get("__main__.fib").?;

    // Test various properties of the identifier (e.g., pc, cairo_type, value, size)
    try expectEqual(@as(?usize, 11), identifier_zero.pc.?);
    try expectEqual(@as(?[]const u8, null), identifier_zero.cairo_type);
    try expect(identifier_zero.decorators.?.len == 0);
    try expectEqual(@as(?usize, null), identifier_zero.size);
    try expectEqual(@as(?[]const u8, null), identifier_zero.full_name);
    try expectEqual(@as(?[]const Reference, null), identifier_zero.references);
    try expectEqual(@as(?json.ArrayHashMap(IdentifierMember), null), identifier_zero.members);
    try expectEqual(@as(?[]const u8, null), identifier_zero.cairo_type);
}

test "ProgramJson: parseProgramJson with missing entry point should return an error" {
    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Obtain the real path of the JSON file
    const path = try std.posix.realpath(
        "cairo_programs/manually_compiled/valid_program_a.json",
        &buffer,
    );

    // Parse the JSON file into a `ProgramJson` structure
    var parsed_program = try ProgramJson.parseFromFile(std.testing.allocator, path);
    // Deallocate parsed_program at the end of the scope
    defer parsed_program.deinit();

    // Specify the entrypoint identifier
    var entrypoint: []const u8 = "missing_function";

    // Expect an error related to an entrypoint not found in the parsed program
    try expectError(
        ProgramError.EntrypointNotFound,
        parsed_program.value.parseProgramJson(
            std.testing.allocator,
            &entrypoint,
            true,
        ),
    );
}

test "ProgramJson: parseProgramJson should parse a valid manually compiled program with an entry point" {
    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Obtain the real path of the JSON file
    const path = try std.posix.realpath(
        "cairo_programs/manually_compiled/valid_program_a.json",
        &buffer,
    );

    // Parse the JSON file into a `ProgramJson` structure
    var parsed_program = try ProgramJson.parseFromFile(std.testing.allocator, path);
    // Deallocate parsed_program at the end of the scope
    defer parsed_program.deinit();

    // Specify the entrypoint identifier
    var entrypoint: []const u8 = "main";

    // Parse the program JSON into a `Program` structure
    var program = try parsed_program.value.parseProgramJson(
        std.testing.allocator,
        &entrypoint,
        true,
    );
    // Deallocate program at the end of the scope
    defer program.deinit(std.testing.allocator);

    // Define an array of expected MaybeRelocatable values
    const expected_data_vec = [_]MaybeRelocatable{
        MaybeRelocatable.fromInt(u256, 5189976364521848832),
        MaybeRelocatable.fromInt(u256, 1000),
        MaybeRelocatable.fromInt(u256, 5189976364521848832),
        MaybeRelocatable.fromInt(u256, 2000),
        MaybeRelocatable.fromInt(u256, 5201798304953696256),
        MaybeRelocatable.fromInt(u256, 2345108766317314046),
    };

    // Expect equality between the expected MaybeRelocatable values and the parsed program data items
    try expectEqualSlices(
        MaybeRelocatable,
        &expected_data_vec,
        program.shared_program_data.data.items,
    );

    // Expect the entrypoint `main` to be at index 0 in the shared_program_data
    try expectEqual(
        @as(usize, 0),
        program.shared_program_data.main,
    );

    // Initialize an AutoHashMap to store the expected hints.
    var expected_hints = std.AutoHashMap(
        usize,
        []const HintParams,
    ).init(std.testing.allocator);
    defer expected_hints.deinit();

    // Put an expected hint at offset 0.
    try expected_hints.put(
        0,
        &[_]HintParams{
            .{
                .code = "memory[ap] = segments.add()",
                .accessible_scopes = &[_][]const u8{
                    "starkware.cairo.common.alloc",
                    "starkware.cairo.common.alloc.alloc",
                },
                .flow_tracking_data = .{
                    .ap_tracking = .{ .group = 0, .offset = 0 },
                    .reference_ids = .{},
                },
            },
        },
    );
    // Put another expected hint at offset 4.
    try expected_hints.put(
        4,
        &[_]HintParams{
            .{
                .code = "import math",
                .accessible_scopes = &[_][]const u8{
                    "__main__",
                    "__main__.main",
                },
                .flow_tracking_data = .{
                    .ap_tracking = .{ .group = 5, .offset = 0 },
                    .reference_ids = .{},
                },
            },
        },
    );

    // Convert the hints collection from the program into an AutoHashMap.
    var hints_hash_map = try program.shared_program_data.hints_collection.intoHashMap(std.testing.allocator);
    defer hints_hash_map.deinit();

    // Ensure that the AutoHashMap has the expected number of hints.
    try expectEqual(@as(usize, 2), hints_hash_map.count());

    // Check the number of hints at offset 0 and compare with the expected hint count.
    try expect(hints_hash_map.get(0).?.len == 1);
    // Compare the expected hint at offset 0 with the actual hint from the AutoHashMap.
    try expectEqualDeep(expected_hints.get(0).?[0], hints_hash_map.get(0).?[0]);

    // Check the number of hints at offset 4 and compare with the expected hint count.
    try expect(hints_hash_map.get(4).?.len == 1);
    // Compare the expected hint at offset 4 with the actual hint from the AutoHashMap.
    try expectEqualDeep(expected_hints.get(4).?[0], hints_hash_map.get(4).?[0]);
}

test "ProgramJson: parseProgramJson should parse a valid manually compiled program without entry point" {
    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Obtain the real path of the JSON file
    const path = try std.posix.realpath(
        "cairo_programs/manually_compiled/valid_program_a.json",
        &buffer,
    );

    // Parse the JSON file into a `ProgramJson` structure
    var parsed_program = try ProgramJson.parseFromFile(std.testing.allocator, path);
    // Deallocate parsed_program at the end of the scope
    defer parsed_program.deinit();

    // Parse the program JSON into a `Program` structure
    var program = try parsed_program.value.parseProgramJson(
        std.testing.allocator,
        null,
        true,
    );
    // Deallocate program at the end of the scope
    defer program.deinit(std.testing.allocator);

    // Define an array of expected MaybeRelocatable values
    const expected_data_vec = [_]MaybeRelocatable{
        MaybeRelocatable.fromInt(u256, 5189976364521848832),
        MaybeRelocatable.fromInt(u256, 1000),
        MaybeRelocatable.fromInt(u256, 5189976364521848832),
        MaybeRelocatable.fromInt(u256, 2000),
        MaybeRelocatable.fromInt(u256, 5201798304953696256),
        MaybeRelocatable.fromInt(u256, 2345108766317314046),
    };

    // Expect equality between the expected MaybeRelocatable values and the parsed program data items
    try expectEqualSlices(
        MaybeRelocatable,
        &expected_data_vec,
        program.shared_program_data.data.items,
    );

    // Expect the entrypoint `main` to be at index null in the shared_program_data
    try expectEqual(
        @as(?usize, null),
        program.shared_program_data.main,
    );

    // Initialize an AutoHashMap to store the expected hints.
    var expected_hints = std.AutoHashMap(
        usize,
        []const HintParams,
    ).init(std.testing.allocator);
    defer expected_hints.deinit();

    // Put an expected hint at offset 0.
    try expected_hints.put(
        0,
        &[_]HintParams{
            .{
                .code = "memory[ap] = segments.add()",
                .accessible_scopes = &[_][]const u8{
                    "starkware.cairo.common.alloc",
                    "starkware.cairo.common.alloc.alloc",
                },
                .flow_tracking_data = .{
                    .ap_tracking = .{ .group = 0, .offset = 0 },
                    .reference_ids = .{},
                },
            },
        },
    );
    // Put another expected hint at offset 4.
    try expected_hints.put(
        4,
        &[_]HintParams{
            .{
                .code = "import math",
                .accessible_scopes = &[_][]const u8{
                    "__main__",
                    "__main__.main",
                },
                .flow_tracking_data = .{
                    .ap_tracking = .{ .group = 5, .offset = 0 },
                    .reference_ids = .{},
                },
            },
        },
    );

    // Convert the hints collection from the program into an AutoHashMap.
    var hints_hash_map = try program.shared_program_data.hints_collection.intoHashMap(std.testing.allocator);
    defer hints_hash_map.deinit();

    // Ensure that the AutoHashMap has the expected number of hints.
    try expectEqual(@as(usize, 2), hints_hash_map.count());

    // Check the number of hints at offset 0 and compare with the expected hint count.
    try expect(hints_hash_map.get(0).?.len == 1);
    // Compare the expected hint at offset 0 with the actual hint from the AutoHashMap.
    try expectEqualDeep(expected_hints.get(0).?[0], hints_hash_map.get(0).?[0]);

    // Check the number of hints at offset 4 and compare with the expected hint count.
    try expect(hints_hash_map.get(4).?.len == 1);
    // Compare the expected hint at offset 4 with the actual hint from the AutoHashMap.
    try expectEqualDeep(expected_hints.get(4).?[0], hints_hash_map.get(4).?[0]);
}

test "ProgramJson: parseProgramJson with constant deserialization" {
    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    // Obtain the real path of the JSON file.
    const path = try std.posix.realpath(
        "cairo_programs/manually_compiled/deserialize_constant_test.json",
        &buffer,
    );

    // Parse the JSON file into a `ProgramJson` structure.
    var parsed_program = try ProgramJson.parseFromFile(std.testing.allocator, path);
    // Deallocate parsed_program at the end of the scope.
    defer parsed_program.deinit();

    // Parse the program JSON into a `Program` structure without specifying an entry point.
    var program = try parsed_program.value.parseProgramJson(
        std.testing.allocator,
        null,
        true,
    );
    // Deallocate program at the end of the scope.
    defer program.deinit(std.testing.allocator);

    // Define and initialize a hashmap for expected identifiers.
    var expected_identifiers = std.StringHashMap(Identifier).init(std.testing.allocator);
    defer expected_identifiers.deinit();

    // Populate the hashmap with expected identifier values.
    try expected_identifiers.put("__main__.main", .{
        .pc = 0,
        .type = "function",
        .value = null,
        .valueFelt = null,
        .full_name = null,
        .members = null,
        .cairo_type = null,
    });

    try expected_identifiers.put("__main__.compare_abs_arrays.SIZEOF_LOCALS", .{
        .pc = null,
        .type = "const",
        .value = -3618502788666131213697322783095070105623107215331596699973092056135872020481,
        .valueFelt = Felt252.fromInt(
            u256,
            3618502788666131213697322783095070105623107215331596699973092056135872020481,
        ).neg(),
        .full_name = null,
        .members = null,
        .cairo_type = null,
    });

    try expected_identifiers.put("starkware.cairo.common.cairo_keccak.keccak.unsigned_div_rem", .{
        .pc = null,
        .type = "alias",
        .value = null,
        .valueFelt = null,
        .full_name = null,
        .members = null,
        .cairo_type = null,
    });

    try expected_identifiers.put("starkware.cairo.common.cairo_keccak.packed_keccak.ALL_ONES", .{
        .pc = null,
        .type = "const",
        .value = -106710729501573572985208420194530329073740042555888586719234,
        .valueFelt = Felt252.fromInt(
            u256,
            106710729501573572985208420194530329073740042555888586719234,
        ).neg(),
        .full_name = null,
        .members = null,
        .cairo_type = null,
    });

    try expected_identifiers.put("starkware.cairo.common.cairo_keccak.packed_keccak.BLOCK_SIZE", .{
        .pc = null,
        .type = "const",
        .value = 3,
        .valueFelt = Felt252.three(),
        .full_name = null,
        .members = null,
        .cairo_type = null,
    });

    try expected_identifiers.put("starkware.cairo.common.alloc.alloc.SIZEOF_LOCALS", .{
        .pc = null,
        .type = "const",
        .value = 0,
        .valueFelt = Felt252.zero(),
        .full_name = null,
        .members = null,
        .cairo_type = null,
    });

    try expected_identifiers.put("starkware.cairo.common.uint256.SHIFT", .{
        .pc = null,
        .type = "const",
        .value = 340282366920938463463374607431768211456,
        .valueFelt = Felt252.fromInt(u256, 340282366920938463463374607431768211456),
        .full_name = null,
        .members = null,
        .cairo_type = null,
    });

    // Check for equality between the counts of expected identifiers and parsed identifiers.
    try expectEqual(
        expected_identifiers.count(),
        program.shared_program_data.identifiers.count(),
    );

    // Create an iterator for identifiers in the parsed program data.
    var identifiers_iterator = program.shared_program_data.identifiers.iterator();

    // Iterate through the parsed identifiers and check against expected values.
    while (identifiers_iterator.next()) |kv| {
        // Retrieve expected and parsed identifiers based on the key.
        const expected_identifier = expected_identifiers.get(kv.key_ptr.*).?;
        const identifier = program.shared_program_data.identifiers.get(kv.key_ptr.*).?;

        // Compare various attributes of the expected and parsed identifiers.
        try expectEqual(expected_identifier.pc, identifier.pc);
        try expectEqualStrings(expected_identifier.type.?, identifier.type.?);
        try expectEqual(expected_identifier.value, identifier.value);
        try expectEqual(expected_identifier.valueFelt, identifier.valueFelt);
        try expectEqual(expected_identifier.full_name, identifier.full_name);
        try expectEqual(expected_identifier.members, identifier.members);
        try expectEqual(expected_identifier.cairo_type, identifier.cairo_type);
    }
}

test "ProgramJson: parseFromString should deserialize attributes properly" {
    // Valid JSON string representing a Cairo v0 program
    const valid_json =
        \\  {
        \\     "prime": "0x800000000000011000000000000000000000000000000000000000000000001",
        \\    "attributes": [
        \\        {
        \\             "accessible_scopes": [
        \\                 "openzeppelin.security.safemath.library",
        \\                 "openzeppelin.security.safemath.library.SafeUint256",
        \\                 "openzeppelin.security.safemath.library.SafeUint256.add"
        \\            ],
        \\             "end_pc": 381,
        \\             "flow_tracking_data": {
        \\                 "ap_tracking": {
        \\                     "group": 14,
        \\                     "offset": 35
        \\                 },
        \\                 "reference_ids": {}
        \\             },
        \\              "name": "error_message",
        \\             "start_pc": 379,
        \\             "value": "SafeUint256: addition overflow"
        \\          },
        \\          {
        \\                        "accessible_scopes": [
        \\                          "openzeppelin.security.safemath.library",
        \\                          "openzeppelin.security.safemath.library.SafeUint256",
        \\                          "openzeppelin.security.safemath.library.SafeUint256.sub_le"
        \\                      ],
        \\                      "end_pc": 404,
        \\                     "flow_tracking_data": {
        \\                          "ap_tracking": {
        \\                              "group": 15,
        \\                              "offset": 60
        \\                          },
        \\                          "reference_ids": {}
        \\                      },
        \\                      "name": "error_message",
        \\                      "start_pc": 402,
        \\                      "value": "SafeUint256: subtraction overflow"
        \\                  }
        \\              ],
        \\             "debug_info": {
        \\                  "instruction_locations": {}
        \\              },
        \\              "builtins": [],
        \\            "data": [
        \\               ],
        \\               "identifiers": {
        \\               },
        \\               "hints": {
        \\               },
        \\               "reference_manager": {
        \\                   "references": [
        \\                   ]
        \\               }
        \\          }
    ;

    // Parsing the JSON string into a `ProgramJson` instance
    var parsed_program = try ProgramJson.parseFromString(std.testing.allocator, valid_json);
    defer parsed_program.deinit();

    // Expected attributes to be parsed from the JSON
    const expected_attributes = [_]Attribute{
        .{
            .name = "error_message",
            .start_pc = 379,
            .end_pc = 381,
            .value = "SafeUint256: addition overflow",
            .flow_tracking_data = .{
                .ap_tracking = .{ .group = 14, .offset = 35 },
                .reference_ids = .{},
            },
        },
        .{
            .name = "error_message",
            .start_pc = 402,
            .end_pc = 404,
            .value = "SafeUint256: subtraction overflow",
            .flow_tracking_data = .{
                .ap_tracking = .{ .group = 15, .offset = 60 },
                .reference_ids = .{},
            },
        },
    };

    // Ensure that the number of parsed attributes matches the number of expected attributes.
    try expect(parsed_program.value.attributes.?.len == expected_attributes.len);

    // Iterating over parsed attributes and checking against expected values
    for (parsed_program.value.attributes.?, 0..) |attribute, i| {
        try expectEqualStrings(expected_attributes[i].name, attribute.name);
        try expectEqual(expected_attributes[i].start_pc, attribute.start_pc);
        try expectEqual(expected_attributes[i].end_pc, attribute.end_pc);
        try expectEqual(
            expected_attributes[i].flow_tracking_data.?.ap_tracking,
            attribute.flow_tracking_data.?.ap_tracking,
        );
        try expectEqual(
            @as(usize, 0),
            attribute.flow_tracking_data.?.reference_ids.?.map.count(),
        );
    }
}

test "ProgramJson: parseFromString should deserialize instruction locations with no parent properly" {
    // Valid JSON string representing a Cairo v0 program
    const valid_json =
        \\    {
        \\            "prime": "0x800000000000011000000000000000000000000000000000000000000000001",
        \\            "attributes": [],
        \\            "debug_info": {
        \\                "file_contents": {},
        \\                "instruction_locations": {
        \\                    "0": {
        \\                        "accessible_scopes": [
        \\                            "starkware.cairo.lang.compiler.lib.registers",
        \\                            "starkware.cairo.lang.compiler.lib.registers.get_fp_and_pc"
        \\                        ],
        \\                        "flow_tracking_data": {
        \\                            "ap_tracking": {
        \\                                "group": 0,
        \\                                "offset": 0
        \\                            },
        \\                            "reference_ids": {}
        \\                        },
        \\                        "hints": [],
        \\                        "inst": {
        \\                            "end_col": 73,
        \\                            "end_line": 7,
        \\                            "input_file": {
        \\                                "filename": "/Users/user/test/env/lib/python3.9/site-packages/starkware/cairo/lang/compiler/lib/registers.cairo"
        \\                            },
        \\                            "start_col": 5,
        \\                            "start_line": 7
        \\                        }
        \\                    },
        \\                    "3": {
        \\                        "accessible_scopes": [
        \\                            "starkware.cairo.common.alloc",
        \\                            "starkware.cairo.common.alloc.alloc"
        \\                        ],
        \\                        "flow_tracking_data": {
        \\                            "ap_tracking": {
        \\                                "group": 1,
        \\                                "offset": 1
        \\                            },
        \\                            "reference_ids": {}
        \\                        },
        \\                        "hints": [],
        \\                        "inst": {
        \\                            "end_col": 40,
        \\                            "end_line": 5,
        \\                            "input_file": {
        \\                                "filename": "/Users/user/test/env/lib/python3.9/site-packages/starkware/cairo/common/alloc.cairo"
        \\                            },
        \\                            "start_col": 5,
        \\                            "start_line": 5
        \\                        }
        \\                    }
        \\                }
        \\            },
        \\            "builtins": [],
        \\            "data": [
        \\            ],
        \\            "identifiers": {
        \\            },
        \\            "hints": {
        \\            },
        \\            "reference_manager": {
        \\                "references": [
        \\                ]
        \\            }
        \\        }
    ;

    // Parsing the JSON string into a `ProgramJson` instance
    var parsed_program = try ProgramJson.parseFromString(std.testing.allocator, valid_json);
    defer parsed_program.deinit();

    // Creating an empty hash map to hold expected instruction locations
    var expected_instructions_location = std.StringHashMap(InstructionLocation).init(std.testing.allocator);
    defer expected_instructions_location.deinit();

    // Adding expected instruction locations to the hash map
    try expected_instructions_location.put(
        "0",
        .{
            .accessible_scopes = &[_][]const u8{
                "starkware.cairo.lang.compiler.lib.registers",
                "starkware.cairo.lang.compiler.lib.registers.get_fp_and_pc",
            },
            .flow_tracking_data = .{
                .ap_tracking = .{ .group = 0, .offset = 0 },
                .reference_ids = .{},
            },
            .hints = &[_]HintLocation{},
            .inst = .{
                .end_col = 73,
                .end_line = 7,
                .input_file = .{
                    .filename = "/Users/user/test/env/lib/python3.9/site-packages/starkware/cairo/lang/compiler/lib/registers.cairo",
                },
                .start_col = 5,
                .start_line = 7,
            },
        },
    );

    // Adding another expected instruction location to the hash map
    try expected_instructions_location.put(
        "3",
        .{
            .accessible_scopes = &[_][]const u8{
                "starkware.cairo.common.alloc",
                "starkware.cairo.common.alloc.alloc",
            },
            .flow_tracking_data = .{
                .ap_tracking = .{ .group = 1, .offset = 1 },
                .reference_ids = .{},
            },
            .hints = &[_]HintLocation{},
            .inst = .{
                .end_col = 40,
                .end_line = 5,
                .input_file = .{
                    .filename = "/Users/user/test/env/lib/python3.9/site-packages/starkware/cairo/common/alloc.cairo",
                },
                .start_col = 5,
                .start_line = 5,
            },
        },
    );

    // Ensure that the count of expected and parsed instruction locations matches
    try expectEqual(
        expected_instructions_location.count(),
        parsed_program.value.debug_info.?.instruction_locations.?.map.count(),
    );

    // Iterator for parsed instruction locations
    var instruction_location_iterator = parsed_program.value.debug_info.?.instruction_locations.?.map.iterator();

    while (instruction_location_iterator.next()) |kv| {
        // Retrieving expected and parsed instruction locations by key
        const expected_instruction_location = expected_instructions_location.get(kv.key_ptr.*);
        const instruction_location = parsed_program.value.debug_info.?.instruction_locations.?.map.get(kv.key_ptr.*);

        // Comparing attributes of expected and parsed instruction locations
        for (instruction_location.?.accessible_scopes, 0..) |accessible_scope, i| {
            // Checking and asserting the equality of accessible scopes
            try expectEqualStrings(
                accessible_scope,
                expected_instruction_location.?.accessible_scopes[i],
            );
        }

        // Asserting the equality of Ap register tracking between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.flow_tracking_data.?.ap_tracking,
            instruction_location.?.flow_tracking_data.?.ap_tracking,
        );

        // Asserting that the reference IDs count of the parsed location's flow tracking data is zero
        try expectEqual(
            @as(usize, 0),
            instruction_location.?.flow_tracking_data.?.reference_ids.?.map.count(),
        );

        // Asserting the equality of HintLocation slices between expected and parsed locations
        try expectEqualSlices(
            HintLocation,
            expected_instruction_location.?.hints,
            instruction_location.?.hints,
        );

        // Asserting the equality of end column attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.end_col,
            instruction_location.?.inst.end_col,
        );
        // Asserting the equality of end line attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.end_line,
            instruction_location.?.inst.end_line,
        );
        // Asserting the equality of input file filename attribute between expected and parsed locations
        try expectEqualStrings(
            expected_instruction_location.?.inst.input_file.filename,
            instruction_location.?.inst.input_file.filename,
        );
        // Asserting the equality of start column attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.start_col,
            instruction_location.?.inst.start_col,
        );
        // Asserting the equality of start line attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.start_line,
            instruction_location.?.inst.start_line,
        );
    }
}

test "ProgramJson: parseFromString should deserialize instruction locations with parent properly" {
    // Valid JSON string representing a Cairo v0 program
    const valid_json =
        \\   {
        \\            "prime": "0x800000000000011000000000000000000000000000000000000000000000001",
        \\            "attributes": [],
        \\            "debug_info": {
        \\                "file_contents": {},
        \\                "instruction_locations": {
        \\                    "4": {
        \\                        "accessible_scopes": [
        \\                            "__main__",
        \\                            "__main__",
        \\                            "__main__.constructor"
        \\                        ],
        \\                        "flow_tracking_data": null,
        \\                        "hints": [],
        \\                        "inst": {
        \\                            "end_col": 36,
        \\                            "end_line": 9,
        \\                            "input_file": {
        \\                                "filename": "test/contracts/cairo/always_fail.cairo"
        \\                            },
        \\                            "parent_location": [
        \\                               {
        \\                                    "end_col": 36,
        \\                                    "end_line": 9,
        \\                                    "input_file": {
        \\                                        "filename": "test/contracts/cairo/always_fail.cairo"
        \\                                    },
        \\                                    "parent_location": [
        \\                                        {
        \\                                            "end_col": 15,
        \\                                            "end_line": 11,
        \\                                            "input_file": {
        \\                                                "filename": "test/contracts/cairo/always_fail.cairo"
        \\                                            },
        \\                                            "start_col": 5,
        \\                                            "start_line": 11
        \\                                        },
        \\                                        "While trying to retrieve the implicit argument 'syscall_ptr' in:"
        \\                                    ],
        \\                                    "start_col": 18,
        \\                                    "start_line": 9
        \\                                },
        \\                                "While expanding the reference 'syscall_ptr' in:"
        \\                            ],
        \\                            "start_col": 18,
        \\                            "start_line": 9
        \\                        }
        \\                    }
        \\                }
        \\            },
        \\            "builtins": [],
        \\            "data": [
        \\            ],
        \\            "identifiers": {
        \\            },
        \\            "hints": {
        \\            },
        \\            "reference_manager": {
        \\                "references": [
        \\                ]
        \\            }
        \\        }
    ;

    // Parsing the JSON string into a `ProgramJson` instance
    var parsed_program = try ProgramJson.parseFromString(std.testing.allocator, valid_json);
    defer parsed_program.deinit();

    // Creating an empty hash map to hold expected instruction locations
    var expected_instructions_location = std.StringHashMap(InstructionLocation).init(std.testing.allocator);
    defer expected_instructions_location.deinit();

    // Adding expected instruction locations to the hash map
    try expected_instructions_location.put(
        "4",
        .{
            .accessible_scopes = &[_][]const u8{
                "__main__",
                "__main__",
                "__main__.constructor",
            },
            .flow_tracking_data = null,
            .hints = &[_]HintLocation{},
            .inst = .{
                .end_col = 36,
                .end_line = 9,
                .input_file = .{ .filename = "test/contracts/cairo/always_fail.cairo" },
                .start_col = 18,
                .start_line = 9,
            },
        },
    );

    // Ensure that the count of expected and parsed instruction locations matches
    try expectEqual(
        expected_instructions_location.count(),
        parsed_program.value.debug_info.?.instruction_locations.?.map.count(),
    );

    // Iterator for parsed instruction locations
    var instruction_location_iterator = parsed_program.value.debug_info.?.instruction_locations.?.map.iterator();

    while (instruction_location_iterator.next()) |kv| {
        // Retrieving expected and parsed instruction locations by key
        const expected_instruction_location = expected_instructions_location.get(kv.key_ptr.*);
        const instruction_location = parsed_program.value.debug_info.?.instruction_locations.?.map.get(kv.key_ptr.*);

        // Comparing attributes of expected and parsed instruction locations
        for (instruction_location.?.accessible_scopes, 0..) |accessible_scope, i| {
            // Checking and asserting the equality of accessible scopes
            try expectEqualStrings(
                accessible_scope,
                expected_instruction_location.?.accessible_scopes[i],
            );
        }

        // Asserting the equality of Ap register tracking between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.flow_tracking_data,
            instruction_location.?.flow_tracking_data,
        );

        // Asserting the equality of HintLocation slices between expected and parsed locations
        try expectEqualSlices(
            HintLocation,
            expected_instruction_location.?.hints,
            instruction_location.?.hints,
        );

        // Asserting the equality of end column attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.end_col,
            instruction_location.?.inst.end_col,
        );
        // Asserting the equality of end line attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.end_line,
            instruction_location.?.inst.end_line,
        );
        // Asserting the equality of input file filename attribute between expected and parsed locations
        try expectEqualStrings(
            expected_instruction_location.?.inst.input_file.filename,
            instruction_location.?.inst.input_file.filename,
        );
        // Asserting the equality of start column attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.start_col,
            instruction_location.?.inst.start_col,
        );
        // Asserting the equality of start line attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.start_line,
            instruction_location.?.inst.start_line,
        );

        // First parent location
        const first_parent_location = instruction_location.?.inst.parent_location.?.array.items[0].object;

        // Assertion: Ensuring the end column of the first parent location matches the expected value 36
        try expectEqual(
            @as(i64, 36),
            first_parent_location.get("end_col").?.integer,
        );

        // Assertion: Ensuring the end line of the first parent location matches the expected value 9
        try expectEqual(
            @as(i64, 9),
            first_parent_location.get("end_line").?.integer,
        );

        // Assertion: Ensuring the filename of the input file of the first parent location matches the expected string
        try expectEqualStrings(
            "test/contracts/cairo/always_fail.cairo",
            first_parent_location.get("input_file").?.object.get("filename").?.string,
        );

        // Assertion: Ensuring the start column of the first parent location matches the expected value 18
        try expectEqual(
            @as(i64, 18),
            first_parent_location.get("start_col").?.integer,
        );

        // Assertion: Ensuring the start line of the first parent location matches the expected value 9
        try expectEqual(
            @as(i64, 9),
            first_parent_location.get("start_line").?.integer,
        );

        // Second parent location
        const second_parent_location = first_parent_location.get("parent_location").?.array.items[0].object;

        // Assertion: Ensuring the end column of the second parent location matches the expected value 15
        try expectEqual(
            @as(i64, 15),
            second_parent_location.get("end_col").?.integer,
        );

        // Assertion: Ensuring the end line of the second parent location matches the expected value 11
        try expectEqual(
            @as(i64, 11),
            second_parent_location.get("end_line").?.integer,
        );

        // Assertion: Ensuring the filename of the input file of the second parent location matches the expected string
        try expectEqualStrings(
            "test/contracts/cairo/always_fail.cairo",
            second_parent_location.get("input_file").?.object.get("filename").?.string,
        );

        // Assertion: Ensuring the start column of the second parent location matches the expected value 5
        try expectEqual(
            @as(i64, 5),
            second_parent_location.get("start_col").?.integer,
        );

        // Assertion: Ensuring the start line of the second parent location matches the expected value 11
        try expectEqual(
            @as(i64, 11),
            second_parent_location.get("start_line").?.integer,
        );
    }
}

test "ProgramJson: Program deserialization with instruction locations containing parent_location" {
    // Valid JSON string representing a Cairo v0 program
    const valid_json =
        \\   {
        \\            "prime": "0x800000000000011000000000000000000000000000000000000000000000001",
        \\            "attributes": [],
        \\            "debug_info": {
        \\                "file_contents": {},
        \\                "instruction_locations": {
        \\                    "4": {
        \\                        "accessible_scopes": [
        \\                            "__main__",
        \\                            "__main__",
        \\                            "__main__.constructor"
        \\                        ],
        \\                        "flow_tracking_data": null,
        \\                        "hints": [],
        \\                        "inst": {
        \\                            "end_col": 36,
        \\                            "end_line": 9,
        \\                            "input_file": {
        \\                                "filename": "test/contracts/cairo/always_fail.cairo"
        \\                            },
        \\                            "parent_location": [
        \\                               {
        \\                                    "end_col": 36,
        \\                                    "end_line": 9,
        \\                                    "input_file": {
        \\                                        "filename": "test/contracts/cairo/always_fail.cairo"
        \\                                    },
        \\                                    "parent_location": [
        \\                                        {
        \\                                            "end_col": 15,
        \\                                            "end_line": 11,
        \\                                            "input_file": {
        \\                                                "filename": "test/contracts/cairo/always_fail.cairo"
        \\                                            },
        \\                                            "start_col": 5,
        \\                                            "start_line": 11
        \\                                        },
        \\                                        "While trying to retrieve the implicit argument 'syscall_ptr' in:"
        \\                                    ],
        \\                                    "start_col": 18,
        \\                                    "start_line": 9
        \\                                },
        \\                                "While expanding the reference 'syscall_ptr' in:"
        \\                            ],
        \\                            "start_col": 18,
        \\                            "start_line": 9
        \\                        }
        \\                    }
        \\                }
        \\            },
        \\            "builtins": [],
        \\            "data": [
        \\            ],
        \\            "identifiers": {
        \\            },
        \\            "hints": {
        \\            },
        \\            "reference_manager": {
        \\                "references": [
        \\                ]
        \\            }
        \\        }
    ;

    // Parsing the JSON string into a `ProgramJson` instance
    var parsed_program = try ProgramJson.parseFromString(std.testing.allocator, valid_json);
    defer parsed_program.deinit();

    // Parse the program JSON into a `Program` structure without specifying an entry point.
    var program = try parsed_program.value.parseProgramJson(
        std.testing.allocator,
        null,
        true,
    );
    // Deallocate program at the end of the scope.
    defer program.deinit(std.testing.allocator);

    // Creating an empty hash map to hold expected instruction locations
    var expected_instructions_location = std.StringHashMap(InstructionLocation).init(std.testing.allocator);
    defer expected_instructions_location.deinit();

    // Create an empty linked list structure to hold `Node`s
    var list = InstructionLinkedList{};

    // Initialize the first `Node` structure for `parent_location_instruction_2`
    var parent_location_instruction_2 = InstructionLinkedList.Node{ .data = .{
        .end_col = 15,
        .end_line = 11,
        .input_file = .{ .filename = "test/contracts/cairo/always_fail.cairo" },
        .start_col = 5,
        .start_line = 11,
    } };

    // Initialize the second `Node` structure for `parent_location_instruction_1`
    var parent_location_instruction_1 = InstructionLinkedList.Node{ .data = .{
        .end_col = 36,
        .end_line = 9,
        .input_file = .{ .filename = "test/contracts/cairo/always_fail.cairo" },
        .start_col = 18,
        .start_line = 9,
    } };

    // Prepend `parent_location_instruction_2` to the linked list
    list.prepend(&parent_location_instruction_2);

    // Prepend `parent_location_instruction_1` to the linked list
    list.prepend(&parent_location_instruction_1);

    // Create an expected instruction location and add it to the hashmap
    try expected_instructions_location.put(
        "4",
        .{
            .accessible_scopes = &[_][]const u8{
                "__main__",
                "__main__",
                "__main__.constructor",
            },
            .flow_tracking_data = null,
            .hints = &[_]HintLocation{},
            .inst = .{
                .end_col = 36,
                .end_line = 9,
                .input_file = .{ .filename = "test/contracts/cairo/always_fail.cairo" },
                .parent_location_instruction = list,
                .start_col = 18,
                .start_line = 9,
            },
        },
    );

    // Ensure the count of expected instructions matches the parsed program's instruction locations
    try expectEqual(
        expected_instructions_location.count(),
        program.getInstructionLocations().?.count(),
    );

    // Iterator for parsed instruction locations
    var it = program.getInstructionLocations().?.iterator();

    // Iterate through the parsed instruction locations
    while (it.next()) |kv| {
        // Retrieve expected and parsed instruction locations by key
        const expected_instruction_location = expected_instructions_location.get(kv.key_ptr.*);
        const instruction_location = program.getInstructionLocation(kv.key_ptr.*);

        // Comparing attributes of expected and parsed instruction locations
        for (instruction_location.?.accessible_scopes, 0..) |accessible_scope, i| {
            // Checking and asserting the equality of accessible scopes
            try expectEqualStrings(
                accessible_scope,
                expected_instruction_location.?.accessible_scopes[i],
            );
        }

        // Asserting the equality of Ap register tracking between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.flow_tracking_data,
            instruction_location.?.flow_tracking_data,
        );

        // Asserting the equality of HintLocation slices between expected and parsed locations
        try expectEqualSlices(
            HintLocation,
            expected_instruction_location.?.hints,
            instruction_location.?.hints,
        );

        // Asserting the equality of end column attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.end_col,
            instruction_location.?.inst.end_col,
        );
        // Asserting the equality of end line attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.end_line,
            instruction_location.?.inst.end_line,
        );
        // Asserting the equality of input file filename attribute between expected and parsed locations
        try expectEqualStrings(
            expected_instruction_location.?.inst.input_file.filename,
            instruction_location.?.inst.input_file.filename,
        );
        // Asserting the equality of start column attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.start_col,
            instruction_location.?.inst.start_col,
        );
        // Asserting the equality of start line attribute between expected and parsed locations
        try expectEqual(
            expected_instruction_location.?.inst.start_line,
            instruction_location.?.inst.start_line,
        );

        // Iterating through the linked list of parent_location_instruction nodes
        var it_actual = instruction_location.?.inst.parent_location_instruction.?.first;
        var it_expected = expected_instruction_location.?.inst.parent_location_instruction.?.first;

        // Loop through the linked list until it_actual reaches the end (null)
        while (it_actual) |node| : (it_actual = node.next) {
            // Asserting the equality of 'end_col' attribute between expected and actual nodes
            try expectEqual(it_expected.?.data.end_col, it_actual.?.data.end_col);

            // Asserting the equality of 'end_line' attribute between expected and actual nodes
            try expectEqual(it_expected.?.data.end_line, it_actual.?.data.end_line);

            // Asserting the equality of 'filename' attribute between expected and actual nodes' input_file
            try expectEqualStrings(
                it_expected.?.data.input_file.filename,
                it_actual.?.data.input_file.filename,
            );

            // Asserting the equality of 'start_col' attribute between expected and actual nodes
            try expectEqual(it_expected.?.data.start_col, it_actual.?.data.start_col);

            // Asserting the equality of 'start_line' attribute between expected and actual nodes
            try expectEqual(it_expected.?.data.start_line, it_actual.?.data.start_line);

            // Move to the next expected node for comparison in the next iteration
            it_expected = it_expected.?.next;
        }
    }
}

test "ProgramJson should be able to parse a sample subset of cairo0 files" {
    const allocator = std.testing.allocator;

    const program_names: []const []const u8 = &[_][]const u8{
        "_keccak",
        "assert_nn",
        "bitwise_recursion",
        "blake2s_felts",
        "cairo_finalize_keccak_block_size_1000",
        "fibonacci",
        "keccak_integration_tests",
        "math_integration_tests",
        "pedersen_test",
        "poseidon_hash",
        "poseidon_multirun",
        "reduce",
        "secp_ec",
        "sha256_test",
        "uint256_integration_tests",
    };

    inline for (program_names) |program_name| {
        const program_path = try std.mem.concat(
            allocator,
            u8,
            &[_][]const u8{ "cairo_programs/", program_name, ".json" },
        );
        defer allocator.free(program_path);
        errdefer std.debug.print("cannot parse program: {s}\n", .{program_path});

        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try std.posix.realpath(program_path, &buffer);
        var parsed_program = try ProgramJson.parseFromFile(allocator, path);
        defer parsed_program.deinit();
    }
}
