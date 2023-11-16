// ************************************************************
// *                       IMPORTS                            *
// ************************************************************

// Core imports.
const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

const Instruction = struct {
    end_col: u8,
    end_line: u8,
    input_file: struct {
        filename: []const u8,
    },
    start_col: u8,
    start_line: u8,
};

const Reference = struct {
    ap_tracking_data: struct {
        group: u8,
        offset: u8,
    },
    pc: u8,
    value: []const u8,
};

const IdentifierMember = struct {
    cairo_type: ?[]const u8 = null,
    offset: ?u8 = null,
    value: ?[]const u8 = null,
};

const Identifier = struct {
    pc: ?u8 = null,
    size: ?u8 = null,
    type: ?[]const u8 = null,
    decorators: ?[]const u8 = null,
    value: ?u8 = null,
    full_name: ?[]const u8 = null,
    references: ?[]const Reference = null,
    members: ?json.ArrayHashMap(IdentifierMember) = null,
    cairo_type: ?[]const u8 = null,
};

pub const Program = struct {
    attributes: []const []const u8,
    builtins: []const []const u8,
    compiler_version: []const u8,
    data: []const []const u8,

    debug_info: struct {
        file_contents: json.ArrayHashMap([]const u8),
        instruction_locations: std.json.Value,
    },

    hints: json.ArrayHashMap([]const u8),
    identifiers: json.ArrayHashMap(Identifier),
    main_scope: []const u8,
    prime: []const u8,

    reference_manager: struct {
        references: []const Reference,
    },

    /// Attempts to intialize `Program` from json file. Caller must call `deinit()` of the returned object to clean up allocated resources.
    ///
    /// # Arguments
    /// - `allocator`: The allocator for reading the json file and parsing it.
    /// - `filename`: The location of the program json file.
    /// # Returns
    /// - `json.Parsed(Program)`: The parsed json program, where the caller is expected to manage allocated resources via calling `deinit()`.
    /// # Errors
    /// - If loading the file fails.
    /// - If the file has incompatible json with respect to the `Program` struct.
    pub fn initFromFile(allocator: Allocator, filename: []const u8) !json.Parsed(Program) {
        const file = try std.fs.cwd().openFile(filename, .{});
        const file_size = try file.getEndPos();
        defer file.close();

        const buffer = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(buffer);

        const parsed = try json.parseFromSlice(Program, allocator, buffer, .{ .allocate = .alloc_always });

        return parsed;
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Program cannot be initialized from nonexistent json file" {
    try expectError(error.FileNotFound, Program.initFromFile(std.testing.allocator, "nonexistent.json"));
}

test "Program can be initialized from json file with correct program data" {
    var allocator = std.testing.allocator;

    // Get the absolute path of the current working directory.
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.os.realpath("cairo-programs/fibonacci.json", &buffer);
    var program = try Program.initFromFile(allocator, path);
    defer program.deinit();
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

    try expectEqual(expected_data.len, program.value.data.len);
    try std.testing.expectEqualDeep(expected_data, program.value.data);
}
