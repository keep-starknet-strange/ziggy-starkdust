const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const MaybeRelocatable = @import("../memory/relocatable.zig").MaybeRelocatable;
const ProgramError = @import("../error.zig").ProgramError;
const Felt252 = @import("../../math/fields/starknet.zig").Felt252;
const Register = @import("../instructions.zig").Register;
const Program = @import("./program.zig").Program;
const HintsCollection = @import("./program.zig").HintsCollection;
const SharedProgramData = @import("./program.zig").SharedProgramData;
const PRIME_STR = @import("../../math/fields/starknet.zig").PRIME_STR;

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
    group: usize,
    /// Reflects Ap register changes within the same `group`.
    offset: usize,

    /// Initializes a new `ApTracking` instance.
    ///
    /// Returns:
    ///     A new `ApTracking` instance with `group` and `offset` set to 0.
    pub fn init() Self {
        return .{ .group = 0, .offset = 0 };
    }
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
    reference_ids: ?json.ArrayHashMap(usize) = null,
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
    /// Code associated with the hint.
    code: []const u8,
    /// Accessible scopes for the hint.
    accessible_scopes: []const u8,
    /// Flow tracking data related to the hint.
    flow_tracking_data: FlowTrackingData,
};

/// Represents an instruction with associated location details.
///
/// This structure defines an instruction with start and end line/column information,
/// an input file reference, and optional parent location details.
const Instruction = struct {
    /// Ending line number of the instruction.
    end_line: u32,
    /// Ending column number of the instruction.
    end_col: u32,
    /// Input file details containing the filename.
    input_file: struct {
        filename: []const u8,
    },
    /// Optional parent location details (defaults to null).
    parent_location: ?json.Value = null,
    /// Starting column number of the instruction.
    start_col: u32,
    /// Starting line number of the instruction.
    start_line: u32,
};

/// Represents a hint location including location details and prefix newline count.
///
/// This structure defines a hint location, incorporating location information
/// and the count of newlines following the "%{" symbol.
const HintLocation = struct {
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
    flow_tracking_data: FlowTrackingData,
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
pub const Reference = struct {
    /// Tracking data for the register associated with the reference.
    ap_tracking_data: ApTracking,
    /// Program counter (pc) tied to the reference (optional, defaults to null).
    pc: ?usize,
    /// Value of the reference.
    value: []const u8,
};

/// Represents a manager for references to memory addresses defined for specific program locations (pcs).
///
/// This structure maintains a list of references (`references`)
pub const ReferenceManager = struct {
    const Self = @This();

    /// List of references managed by the `ReferenceManager`.
    references: std.ArrayList(Reference),

    /// Initializes a new `ReferenceManager` instance.
    ///
    /// # Params:
    ///   - `allocator`: The allocator used to initialize the instance.
    pub fn init(allocator: Allocator) Self {
        return .{ .references = std.ArrayList(Reference).init(allocator) };
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
    /// Decorators related to the identifier (optional, defaults to null).
    decorators: ?[]const []const u8 = null,
    /// Value associated with the identifier (optional, defaults to null).
    value: ?usize = null,
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

/// Represents a program in JSON format.
pub const ProgramJson = struct {
    const Self = @This();
    /// List of attributes.
    attributes: []Attribute,
    /// List of builtins.
    builtins: []BuiltinName,
    /// Compiler version information.
    compiler_version: []const u8,
    /// Program data.
    data: []const []const u8,
    /// Debug information.
    debug_info: struct {
        /// File contents associated with debug information.
        file_contents: json.ArrayHashMap([]const u8),
        /// Instruction locations linked with debug information.
        instruction_locations: json.ArrayHashMap(InstructionLocation),
    },
    /// Hints associated with the program.
    hints: json.ArrayHashMap([]const HintParams),
    /// Identifiers within the program.
    identifiers: json.ArrayHashMap(Identifier),
    // identifiers: std.StringHashMap(Identifier),
    /// Main scope details.
    main_scope: []const u8,
    /// Prime data.
    prime: []const u8,
    /// Reference manager containing references.
    reference_manager: struct {
        /// List of references.
        references: []const Reference,
    },

    /// Attempts to parse the compilation artifact of a cairo v0 program
    ///
    /// # Arguments
    /// - `allocator`: The allocator for reading the json file and parsing it.
    /// - `filename`: The location of the program json file.
    ///
    /// # Returns
    /// - a parsed ProgramJson
    ///
    /// # Errors
    /// - If loading the file fails.
    /// - If the file has incompatible json with respect to the `ProgramJson` struct.
    pub fn parseFromFile(allocator: Allocator, filename: []const u8) !json.Parsed(Self) {
        const file = try std.fs.cwd().openFile(filename, .{});
        const file_size = try file.getEndPos();
        defer file.close();

        const buffer = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(buffer);

        const parsed = try json.parseFromSlice(
            Self,
            allocator,
            buffer,
            .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            },
        );
        errdefer parsed.deinit();

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
    pub fn parseProgramJson(self: *Self, allocator: Allocator, entrypoint: ?*[]const u8) !Program {
        if (!std.mem.eql(u8, PRIME_STR, self.prime))
            return ProgramError.PrimeDiffers;

        // Finds the program counter of the specified entrypoint identifier.
        // Returns an error if the identifier is not found.
        const entrypoint_pc = if (entrypoint) |e| blk: {
            const key = try std.mem.concat(
                allocator,
                u8,
                &[_][]const u8{ "__main__.", e.* },
            );
            defer allocator.free(key);

            if (self.identifiers.map.get(key)) |entrypoint_identifier| {
                break :blk entrypoint_identifier.pc;
            } else {
                return ProgramError.EntrypointNotFound;
            }
        } else null;

        const start = if (self.identifiers.map.get("__main__.__start__")) |identifier| identifier.pc else null;
        const end = if (self.identifiers.map.get("__main__.__end__")) |identifier| identifier.pc else null;

        var constants = std.StringHashMap(Felt252).init(allocator);
        errdefer constants.deinit();
        // Populates the constants hashmap with identifier keys and associated constant values.
        for (self.identifiers.map.keys(), self.identifiers.map.values()) |key, value| {
            if (value.type) |_| {
                try constants.put(
                    key,
                    if (value.value) |v| Felt252.fromInteger(v) else return ProgramError.ConstWithoutValue,
                );
            }
        }

        // Collects attributes named "error_message" and adds them to error_message_attributes.
        var error_message_attributes = std.ArrayList(Attribute).init(allocator);
        errdefer error_message_attributes.deinit();
        for (0..self.attributes.len) |i| {
            const name = self.attributes[i].name;
            if (std.mem.eql(u8, name, "error_message")) {
                try error_message_attributes.append(self.attributes[i]);
            }
        }

        var builtins = std.ArrayList(BuiltinName).init(allocator);
        errdefer builtins.deinit();
        // Collects built-in names and adds them to the builtins list.
        for (0..self.attributes.len) |i| {
            try builtins.append(self.builtins[i]);
        }

        var instruction_locations = std.StringHashMap(InstructionLocation).init(allocator);
        errdefer instruction_locations.deinit();
        // Populates the instruction_locations hashmap with debug information related to instruction locations.
        for (self.debug_info.instruction_locations.map.keys(), self.debug_info.instruction_locations.map.values()) |key, value| {
            try instruction_locations.put(key, value);
        }

        var identifiers = std.StringHashMap(Identifier).init(allocator);
        errdefer identifiers.deinit();
        // Populates the identifiers hashmap with program identifiers and associated metadata.
        for (self.identifiers.map.keys(), self.identifiers.map.values()) |key, value| {
            try identifiers.put(key, value);
        }

        var hints_collection = HintsCollection.init(allocator);
        errdefer hints_collection.deinit();

        return .{
            .shared_program_data = .{
                .data = self.data,
                .hints_collection = hints_collection,
                .main = entrypoint_pc,
                .start = start,
                .end = end,
                .error_message_attributes = error_message_attributes,
                .instruction_locations = instruction_locations,
                .identifiers = identifiers,
                .reference_manager = try Program.getReferenceList(
                    allocator,
                    &self.reference_manager.references,
                ),
            },
            .constants = constants,
            .builtins = builtins,
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
        var parsed_data = std.ArrayList(MaybeRelocatable).init(allocator);
        errdefer parsed_data.deinit();

        for (self.data) |instruction| {
            try parsed_data.append(MaybeRelocatable.fromU256(try std.fmt.parseInt(
                u256,
                instruction[2..],
                16,
            )));
        }
        return parsed_data;
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
    const allocator = std.testing.allocator;

    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.realpath("cairo_programs/fibonacci.json", &buffer);
    var parsed_program = try ProgramJson.parseFromFile(allocator, path);
    defer parsed_program.deinit();

    const data = try parsed_program.value.readData(allocator);
    defer data.deinit();

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

    try expectEqual(expected_data.len, data.items.len);

    for (0..expected_data.len) |idx| {
        var hex_list = std.ArrayList(u8).init(allocator);
        defer hex_list.deinit();

        const instruction = data.items[idx].felt.toInteger();
        // Format the integer as hexadecimal and store in buffer
        try std.fmt.format(hex_list.writer(), "0x{x}", .{instruction});

        try expectEqualStrings(expected_data[idx], hex_list.items);
    }
}

test "ProgramJson: parseProgramJson should parse a Cairo v0 JSON Program and convert it to a Program" {
    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.realpath("cairo_programs/fibonacci.json", &buffer);
    // Parse the JSON file into a `ProgramJson` structure
    var parsed_program = try ProgramJson.parseFromFile(std.testing.allocator, path);
    defer parsed_program.deinit();

    // Specify the entrypoint identifier
    var entrypoint: []const u8 = "main";
    // Parse the program JSON into a `Program` structure
    var program = try parsed_program.value.parseProgramJson(
        std.testing.allocator,
        &entrypoint,
    );
    defer program.deinit();

    // Test the builtins count
    try expect(program.builtins.items.len == 0);

    // Test the count of constants within the program
    try expectEqual(@as(usize, 17), program.constants.count());

    // Test individual constant values within the program
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.Args").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.ImplicitArgs").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.Return").?);
    try expectEqual(Felt252.fromInteger(0), program.constants.get("__main__.fib.SIZEOF_LOCALS").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.fib_body").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.first_element").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.n").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.result").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.second_element").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.fib.y").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.main").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.main.Args").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.main.ImplicitArgs").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.main.Return").?);
    try expectEqual(Felt252.fromInteger(0), program.constants.get("__main__.main.SIZEOF_LOCALS").?);
    try expectEqual(Felt252.fromInteger(11111111), program.constants.get("__main__.main.result").?);

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
        program.shared_program_data.instruction_locations.?.count(),
    );

    // Test a specific instruction location within shared_program_data
    const instruction_location_0 = program.shared_program_data.instruction_locations.?.get("0").?;

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
        instruction_location_0.flow_tracking_data.ap_tracking,
    );

    // Test the count of reference_ids within flow_tracking_data
    try expectEqual(
        @as(usize, 0),
        instruction_location_0.flow_tracking_data.reference_ids.?.map.count(),
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
    try expectEqual(@as(?usize, 11111111), identifier_zero.value.?);
    try expectEqual(@as(?usize, null), identifier_zero.size);
    try expectEqual(@as(?[]const u8, null), identifier_zero.full_name);
    try expectEqual(@as(?[]const Reference, null), identifier_zero.references);
    try expectEqual(@as(?json.ArrayHashMap(IdentifierMember), null), identifier_zero.members);
    try expectEqual(@as(?[]const u8, null), identifier_zero.cairo_type);
}
