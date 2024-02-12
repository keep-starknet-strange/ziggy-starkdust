const std = @import("std");
const Allocator = std.mem.Allocator;
const Register = @import("../vm/instructions.zig").Register;
const OffsetValue = @import("../vm/types/programjson.zig").OffsetValue;
const ValueAddress = @import("../vm/types/programjson.zig").ValueAddress;
const Felt252 = @import("../math/fields/starknet.zig").Felt252;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualDeep = std.testing.expectEqualDeep;

/// Represents the result of parsing brackets within a byte array.
pub const ParseOptResult = struct { extracted_content: []const u8, is_parsed: bool };

/// Represents the result of parsing the first argument of a 'cast' expression.
pub const CastArgs = struct { first: []const u8, rest: []const u8 };

/// Represents the result of parsing a register from a byte array.
pub const ParseRegisterResult = struct { remaining_input: []const u8, register: ?Register };

pub const ParseOffsetResult = struct { remaining_input: []const u8, offset: i32 };

/// Represents the result of parsing the inner dereference expression.
pub const OffsetValueResult = struct { remaining_input: []const u8, offset_value: OffsetValue };

/// Represents the result of parsing a register and its offset from a byte array.
pub const RegisterOffsetResult = struct { []const u8, ?Register, i32 };

/// Represents the error that can occur during deserialization.
pub const DeserializationError = error{CastDeserialization};

/// Parses the outermost brackets within a byte array.
///
/// This function takes a byte array `input` and attempts to extract the content enclosed within
/// the outermost square brackets ('[' and ']'). If the brackets are properly formatted and found,
/// it returns a `ParseOptResult` tuple containing the extracted content and a boolean indicating
/// successful parsing.
///
/// If no brackets are found or if the brackets are improperly formatted, it returns a `ParseOptResult`
/// containing the original `input` and a `false` boolean value.
///
/// # Parameters
/// - `input`: A byte array in which outer brackets need to be parsed.
///
/// # Returns
/// A `ParseOptResult` tuple containing the content within the outer brackets (if found) and a boolean
/// indicating successful parsing.
pub fn outerBrackets(input: []const u8) ParseOptResult {
    // Split the input array at each '[' character
    var it_in = std.mem.splitSequence(u8, input, "[");

    // Split the input array at each ']' character, searching backward
    var it_out = std.mem.splitBackwardsSequence(u8, input, "]");

    // Empty string ("") case
    if (std.mem.eql(u8, input, ""))
        // No brackets found, return the original input with a false boolean value
        return .{ .extracted_content = input, .is_parsed = false };

    // Refine the check to ensure that the match is the beginning and end of the string
    if (std.mem.eql(u8, it_in.first(), "") and std.mem.eql(u8, it_out.first(), "")) {
        // Return a tuple containing the content within the outer brackets and true
        return .{ .extracted_content = input[it_in.index.?..it_out.index.?], .is_parsed = true };
    }

    // If the above conditions are not met, return the original input with a false boolean value
    return .{ .extracted_content = input, .is_parsed = false };
}

/// Takes the content of a `cast` expression from a byte array.
///
/// This function takes a byte array `input` and attempts to extract the content enclosed within
/// a `cast(...)` expression. If the expression is properly formatted and found, it returns the
/// content of the `cast` expression. Otherwise, it returns a `DeserializationError` indicating
/// failed deserialization.
///
/// # Parameters
/// - `input`: A byte array in which a `cast` expression needs to be parsed.
///
/// # Returns
/// A byte array containing the content of the `cast` expression.
/// An error of type `DeserializationError.CastDeserialization` in case of failed deserialization.
pub fn takeCast(input: []const u8) ![]const u8 {
    // Check for empty input
    if (std.mem.eql(u8, input, ""))
        return DeserializationError.CastDeserialization;

    // Split the input array at each 'cast(' character
    var it_in = std.mem.splitSequence(u8, input, "cast(");

    // Split the input array at each ')' character, searching backward
    var it_out = std.mem.splitBackwardsSequence(u8, input, ")");

    // Check if the split results match the beginning and end of the string
    if (std.mem.eql(u8, it_in.first(), "") and std.mem.eql(u8, it_out.first(), "")) {
        // Return the content of the 'cast' expression
        return input[it_in.index.?..it_out.index.?];
    }

    // Return an error indicating failed deserialization for the 'cast' expression
    return DeserializationError.CastDeserialization;
}

/// Extracts and parses the first argument of a 'cast' expression.
///
/// This function takes a byte array `input`, which is expected to be a valid 'cast' expression,
/// and attempts to extract and parse the first argument within the parentheses. The first argument
/// is expected to be separated by a comma (','). The result is a `CastArgs` tuple containing the
/// trimmed content of the first and remaining arguments.
///
/// # Parameters
/// - `input`: A byte array representing a 'cast' expression.
///
/// # Returns
/// A `CastArgs` tuple containing the trimmed content of the first and remaining arguments.
pub fn takeCastFirstArg(input: []const u8) !CastArgs {
    // Split the 'cast' expression using the `takeCast` function.
    var it = std.mem.splitSequence(
        u8,
        try takeCast(input),
        ",",
    );

    // Return a tuple containing the trimmed content of the first and remaining arguments.
    return .{
        .first = std.mem.trim(u8, it.first(), " "),
        .rest = std.mem.trim(u8, it.rest(), " "),
    };
}

/// Parses the offset properly.
///
/// This function takes a byte array `input` and attempts to parse the offset enclosed within parentheses.
/// The offset can be a positive or negative integer. If the parsing is successful, it returns the parsed offset
/// as an `i32`. Otherwise, it returns a `DeserializationError.CastDeserialization`.
///
/// # Parameters
/// - `input`: A byte array containing the offset to be parsed.
///
/// # Returns
/// The parsed offset as an `i32`.
/// An error of type `DeserializationError.CastDeserialization` in case of failed parsing.
pub fn parseOffset(input: []const u8) !ParseOffsetResult {
    // Check for empty input
    if (std.mem.eql(u8, input, "")) {
        return .{ .remaining_input = "", .offset = 0 };
    }

    var sign: i32 = 1;
    var index_after_sign: usize = 0;

    // Iterate over the input to find the end of whitespaces and determine the sign
    for (input, 0..) |c, i| {
        // Searching end of whitespaces
        if (c != 32) {
            // Minus sign (no change for plus sign)
            if (c == 45 or c == 43) {
                index_after_sign = i + 1;
                if (c == 45) sign = -1;
            }

            break;
        }
    }

    // Extract content without the sign
    const without_sign = std.mem.trim(
        u8,
        input[index_after_sign..],
        " ",
    );

    const idx_next_whitespace = std.mem.indexOf(u8, without_sign, " ") orelse
        without_sign.len;

    // Trim parentheses from both sides
    const without_parenthesis = std.mem.trimRight(
        u8,
        std.mem.trimLeft(u8, without_sign[0..idx_next_whitespace], "("),
        ")",
    );

    // std.debug.print("tutututututu = {any}\n", .{idx_next_whitespace});
    // std.debug.print("without_sign = {s}\n", .{without_sign});
    // std.debug.print("without_sign[idx_next_whitespace..] = {s}\n", .{without_sign[idx_next_whitespace..]});
    // std.debug.print("without_parenthesis = {s}\n", .{without_parenthesis});

    // Parse the offset and apply the sign
    return .{
        .remaining_input = without_sign[idx_next_whitespace..],
        .offset = sign * try std.fmt.parseInt(i32, without_parenthesis, 10),
    };
}

/// Parses a register from a byte array.
///
/// This function takes a byte array `input` and attempts to identify and parse a register
/// representation within it. It recognizes registers such as "ap" and "fp". If a valid register
/// is found, it returns the corresponding `Register` enum variant along with the remaining input;
/// otherwise, it returns `null`.
///
/// # Parameters
/// - `input`: A byte array where a register needs to be parsed.
///
/// # Returns
/// A `ParseRegisterResult` struct containing a `Register` enum variant and the remaining input
/// if a valid register is found; otherwise, returns `null`.
pub fn parseRegister(input: []const u8) ParseRegisterResult {
    // Check for the presence of "ap" in the input
    if (std.mem.indexOf(u8, input, "ap")) |idx|
        return .{ .remaining_input = input[idx + 2 ..], .register = .AP };

    // Check for the presence of "fp" in the input
    if (std.mem.indexOf(u8, input, "fp")) |idx|
        return .{ .remaining_input = input[idx + 2 ..], .register = .FP };

    // If no valid register is found, return `null`
    return .{ .remaining_input = input, .register = null };
}

/// Parses a register and its offset from a byte array.
///
/// This function takes a byte array `input` and attempts to identify and parse a register
/// representation along with its offset within it. It first parses the register using the
/// `parseRegister` function, and then attempts to parse the offset using the `parseOffset`
/// function. If both parsing operations succeed, it returns a `RegisterOffsetResult` containing
/// the parsed register and its offset; otherwise, it propagates any errors encountered during
/// parsing.
///
/// # Parameters
/// - `input`: A byte array where a register and its offset need to be parsed.
///
/// # Returns
/// A `RegisterOffsetResult` containing the parsed register and its offset, or an error if parsing fails.
pub fn parseRegisterAndOffset(input: []const u8) !RegisterOffsetResult {
    const register = parseRegister(input);
    const offset = try parseOffset(register.remaining_input);
    return .{ offset.remaining_input, register.register, offset.offset };
}

/// Parses the inner dereference expression from a byte array.
///
/// This function takes a byte array `input` representing an inner dereference expression,
/// such as `[fp + 1]`, and parses it into its components. It extracts the register and offset
/// using the `parseRegisterAndOffset` function and returns an `OffsetValueResult`
/// containing the remaining input and the parsed offset value or reference.
///
/// # Parameters
/// - `input`: A byte array representing the inner dereference expression.
///
/// # Returns
/// An `OffsetValueResult` containing the remaining input and the parsed offset value or reference.
pub fn innerDereference(input: []const u8) !OffsetValueResult {
    // Check if input is an empty string
    if (std.mem.eql(u8, input, "")) {
        return .{ .remaining_input = "", .offset_value = .{ .value = 0 } };
    }

    // Find the first occurrence of ']' character
    const last_bracket = std.mem.indexOf(u8, input, "]") orelse input.len;

    // Trim whitespace and '[' characters from the left side of the input
    const without_brackets = std.mem.trimLeft(
        u8,
        input[0..last_bracket], // Trim input up to the last ']'
        "[",
    );

    // Check if the input is the same after removing brackets and whitespace
    if (std.mem.eql(u8, input, without_brackets)) return error.noInnerDereference;

    // Extract the register and offset from the input
    const register_and_offset = try parseRegisterAndOffset(without_brackets);

    // Trim whitespace and ']' characters from the left side of the remaining input
    const rem = std.mem.trimLeft(u8, input[last_bracket..], "]");

    // Determine if the parsed register is valid and create the appropriate offset value or reference
    const offset_value: OffsetValue = if (register_and_offset[1]) |r|
        // Create a reference
        .{ .reference = .{ r, register_and_offset[2], true } }
    else
        // Create a simple offset value
        .{ .value = register_and_offset[2] };

    // Return the remaining input and the offset value or reference
    return .{ .remaining_input = rem, .offset_value = offset_value };
}

/// Parses a byte array to determine if it contains a dereference expression.
///
/// This function takes a byte array `input` representing a potential dereference expression,
/// such as "fp + 1", and attempts to parse it into its components. It extracts the register
/// and offset using the `parseRegisterAndOffset` function and returns a `OffsetValueResult`
/// containing the remaining input and the parsed offset value or reference, without considering
/// inner dereference expressions.
///
/// # Parameters
/// - `input`: A byte array representing a potential dereference expression.
///
/// # Returns
/// A `OffsetValueResult` containing the remaining input and the parsed offset value or reference,
/// without considering inner dereference expressions.
pub fn noInnerDereference(input: []const u8) !OffsetValueResult {
    // Extract the register and offset from the input
    const register_and_offset = try parseRegisterAndOffset(input);

    // Determine if the parsed register is valid and create the appropriate offset value or reference
    const offset_value: OffsetValue = if (register_and_offset[1]) |r|
        // Create a reference
        .{ .reference = .{ r, register_and_offset[2], false } }
    else
        // Create a simple offset value
        .{ .value = register_and_offset[2] };

    // Return the remaining input and the offset value or reference
    return .{ .remaining_input = register_and_offset[0], .offset_value = offset_value };
}

pub fn parseValue(input: []const u8, allocator: Allocator) !ValueAddress {
    const without_brackets = outerBrackets(input);
    const first_arg = try takeCastFirstArg(without_brackets.extracted_content);
    const first_offset_value = innerDereference(first_arg.first) catch
        noInnerDereference(first_arg.first) catch
        null;
    const second_offset_value = if (first_offset_value) |ov|
        innerDereference(ov.remaining_input) catch
            noInnerDereference(ov.remaining_input) catch
            null
    else
        null;

    const star_index = std.mem.indexOf(u8, first_arg.rest, "*") orelse first_arg.rest.len;

    const indirection_level = first_arg.rest[star_index..];
    const struct_ = first_arg.rest[0..star_index];

    const type_ = if (indirection_level.len > 1) blk: {
        const t = try std.mem.concat(
            allocator,
            u8,
            &[_][]const u8{ struct_, indirection_level[1..] },
        );
        errdefer allocator.free(t);

        break :blk t;
    } else struct_;

    const first_offset: OffsetValue = if (first_offset_value) |ov| ov.offset_value else .{ .value = 0 };
    const second_offset: OffsetValue = if (second_offset_value) |ov| ov.offset_value else .{ .value = 0 };

    const offsets: std.meta.Tuple(&.{ OffsetValue, OffsetValue }) = if (std.mem.eql(u8, struct_, "felt") and indirection_level.len == 0)
        .{
            switch (first_offset) {
                .immediate => |imm| .{ .immediate = imm },
                .value => |val| .{ .immediate = if (val < 0)
                    Felt252.fromInt(u32, @intCast(-val)).neg()
                else
                    Felt252.fromInt(u32, @intCast(val)) },
                .reference => |ref| .{ .reference = ref },
            },
            switch (second_offset) {
                .immediate => |imm| .{ .immediate = imm },
                .value => |val| .{ .immediate = if (val < 0)
                    Felt252.fromInt(u32, @intCast(-val)).neg()
                else
                    Felt252.fromInt(u32, @intCast(val)) },
                .reference => |ref| .{ .reference = ref },
            },
        }
    else
        .{ first_offset, second_offset };

    return .{
        .offset1 = offsets[0],
        .offset2 = offsets[1],
        .dereference = without_brackets.is_parsed,
        .value_type = type_,
    };
}

test "outerBrackets: should check if the input has outer brackets" {
    // Check if the content within the outer brackets is extracted correctly
    try expectEqualDeep(
        ParseOptResult{ .extracted_content = "cast([fp])", .is_parsed = true },
        outerBrackets("[cast([fp])]"),
    );

    // Check if the function returns the input itself as no outer brackets are present
    try expectEqualDeep(
        ParseOptResult{ .extracted_content = "cast([fp])", .is_parsed = false },
        outerBrackets("cast([fp])"),
    );

    // Check if the function returns an empty string as there are no brackets
    try expectEqualDeep(
        ParseOptResult{ .extracted_content = "", .is_parsed = false },
        outerBrackets(""),
    );

    // Check if the function returns an empty string as there are no brackets
    try expectEqualDeep(
        ParseOptResult{ .extracted_content = "", .is_parsed = true },
        outerBrackets("[]"),
    );
}

test "takeCast: should extract the part inside cast and parenthesis" {
    // Test case 1: Extracting content from a well-formed `cast` expression.
    try expectEqualStrings(
        "[fp + (-1)], felt*",
        try takeCast("cast([fp + (-1)], felt*)"),
    );

    // Test case 2: Extracting complex content from a well-formed `cast` expression.
    try expectEqualStrings(
        "([ap + (-53)] + [ap + (-52)] + [ap + (-51)] - [[ap + (-43)] + 68]) * (-1809251394333065606848661391547535052811553607665798349986546028067936010240), felt",
        try takeCast("cast(([ap + (-53)] + [ap + (-52)] + [ap + (-51)] - [[ap + (-43)] + 68]) * (-1809251394333065606848661391547535052811553607665798349986546028067936010240), felt)"),
    );

    // Test case 3: Error case, attempting to extract from a non-`cast` expression.
    try expectError(
        DeserializationError.CastDeserialization,
        takeCast("[fp + (-1)], felt*"),
    );

    // Test case 4: Error case, attempting to extract from a partially well-formed `cast` expression.
    try expectError(
        DeserializationError.CastDeserialization,
        takeCast("([fp + (-1)], felt*)"),
    );

    // Test case 5: Error case, attempting to extract from an empty input.
    try expectError(
        DeserializationError.CastDeserialization,
        takeCast(""),
    );

    // Test case 6: Error case, attempting to extract from a non-`cast` expression with a single character.
    try expectError(
        DeserializationError.CastDeserialization,
        takeCast("n"),
    );
}

test "takeCastFirstArg: should extract the two arguments of cast" {
    // Test case 1: Valid 'cast' expression with two arguments.
    try expectEqualDeep(
        CastArgs{ .first = "[fp + (-1)]", .rest = "felt*" },
        try takeCastFirstArg("cast([fp + (-1)], felt*)"),
    );

    // Test case 2: Valid 'cast' expression with complex expressions as arguments.
    try expectEqualDeep(
        CastArgs{
            .first = "([ap + (-53)] + [ap + (-52)] + [ap + (-51)] - [[ap + (-43)] + 68]) * (-1809251394333065606848661391547535052811553607665798349986546028067936010240)",
            .rest = "felt",
        },
        try takeCastFirstArg("cast(([ap + (-53)] + [ap + (-52)] + [ap + (-51)] - [[ap + (-43)] + 68]) * (-1809251394333065606848661391547535052811553607665798349986546028067936010240), felt)"),
    );

    // Test case 3: Invalid 'cast' expression with insufficient arguments.
    try expectError(
        DeserializationError.CastDeserialization,
        takeCastFirstArg("n"),
    );
}

test "parseOffset: should correctly parse positive and negative offsets" {
    // Test case: Should correctly parse a negative offset with parentheses
    try expectEqualDeep(
        ParseOffsetResult{ .remaining_input = "", .offset = -1 },
        try parseOffset(" + (-1)"),
    );

    // Test case: Should correctly parse a positive offset
    try expectEqualDeep(
        ParseOffsetResult{ .remaining_input = "", .offset = 1 },
        try parseOffset(" + 1"),
    );

    // Test case: Should correctly parse a negative offset without parentheses
    try expectEqualDeep(
        ParseOffsetResult{ .remaining_input = "", .offset = -1 },
        try parseOffset(" - 1"),
    );

    // Test case: Should handle an empty input, resulting in offset 0
    try expectEqualDeep(
        ParseOffsetResult{ .remaining_input = "", .offset = 0 },
        try parseOffset(""),
    );

    // Test case: Should correctly parse a negative offset with a leading plus sign
    try expectEqualDeep(
        ParseOffsetResult{ .remaining_input = "", .offset = -3 },
        try parseOffset("+ (-3)"),
    );

    // Test case: Should correctly parse a positive offset without parentheses.
    try expectEqualDeep(
        ParseOffsetResult{ .remaining_input = "", .offset = 825323 },
        try parseOffset("825323"),
    );

    try expectEqualDeep(
        ParseOffsetResult{ .remaining_input = " + (-1)", .offset = 0 },
        try parseOffset(" - 0 + (-1)"),
    );
}

test "parseRegister: should correctly identify and parse registers" {
    // Test case: Register "fp" is present in the input
    try expectEqualDeep(
        ParseRegisterResult{ .remaining_input = " + (-1)", .register = .FP },
        parseRegister("fp + (-1)"),
    );

    // Test case: Register "ap" is present in the input
    try expectEqualDeep(
        ParseRegisterResult{ .remaining_input = " + (-1)", .register = .AP },
        parseRegister("ap + (-1)"),
    );

    // Test case: Register "fp" is present in the input with a different offset
    try expectEqualDeep(
        ParseRegisterResult{ .remaining_input = " + (-3)", .register = .FP },
        parseRegister("fp + (-3)"),
    );

    // Test case: Register "ap" is present in the input with a different offset
    try expectEqualDeep(
        ParseRegisterResult{ .remaining_input = " + (-9)", .register = .AP },
        parseRegister("ap + (-9)"),
    );

    try expectEqualDeep(
        ParseRegisterResult{ .remaining_input = " - 0 + (-1)", .register = .AP },
        parseRegister("ap - 0 + (-1)"),
    );
}

test "parseRegisterAndOffset: should correctly identify and parse register and offset" {
    // Test case: Register "fp" is present in the input with an offset of 1
    try expectEqualDeep(RegisterOffsetResult{ "", .FP, 1 }, parseRegisterAndOffset("fp + 1"));

    // Test case: Register "ap" is present in the input with an offset of -1
    try expectEqualDeep(RegisterOffsetResult{ "", .AP, -1 }, parseRegisterAndOffset("ap + (-1)"));

    // Test case: No register is present in the input with an offset of 2
    try expectEqualDeep(RegisterOffsetResult{ "", null, 2 }, parseRegisterAndOffset(" + 2"));

    // Test case: No register is present in the input with an offset of 825323.
    try expectEqualDeep(RegisterOffsetResult{ "", null, 825323 }, try parseRegisterAndOffset("825323"));

    try expectEqualDeep(
        RegisterOffsetResult{ " + (-1)", .AP, 0 },
        try parseRegisterAndOffset("ap - 0 + (-1)"),
    );

    // std.debug.print("finiiiiiiii = {any}\n", .{try parseRegisterAndOffset("ap - 0 + (-1)")});
}

test "innerDereference: should correctly identify and parse OffsetValue" {
    // Test case: Inner dereference expression "[fp + (-1)] + 2"
    try expectEqualDeep(
        OffsetValueResult{
            .remaining_input = " + 2",
            .offset_value = .{ .reference = .{ .FP, -1, true } },
        },
        try innerDereference("[fp + (-1)] + 2"),
    );

    // Test case: Inner dereference expression "[ap + (-2)] + 9223372036854775808"
    try expectEqualDeep(
        OffsetValueResult{
            .remaining_input = " + 9223372036854775808",
            .offset_value = .{ .reference = .{ .AP, -2, true } },
        },
        try innerDereference("[ap + (-2)] + 9223372036854775808"),
    );

    // Test case: Inner dereference expression ""
    try expectEqualDeep(
        OffsetValueResult{
            .remaining_input = "",
            .offset_value = .{ .value = 0 },
        },
        try innerDereference(""),
    );

    // Test case: Inner dereference expression without brackets
    try expectError(
        error.noInnerDereference,
        innerDereference("ap + 2"),
    );

    try expectEqualDeep(
        OffsetValueResult{
            .remaining_input = " + [fp + 1]",
            .offset_value = .{ .reference = .{ .AP, 0, true } },
        },
        try innerDereference("[ap] + [fp + 1]"),
    );
}

test "noInnerDereference: should correctly identify and parse OffsetValue with no inner" {
    // Test case: Dereference expression "ap + 3" with no inner dereference
    try expectEqualDeep(
        OffsetValueResult{
            .remaining_input = "",
            .offset_value = .{ .reference = .{ .AP, 3, false } },
        },
        try noInnerDereference("ap + 3"),
    );

    // Test case: No register is present in the input with an offset of 2
    try expectEqualDeep(
        OffsetValueResult{
            .remaining_input = "",
            .offset_value = .{ .value = 2 },
        },
        try noInnerDereference(" + 2"),
    );

    try expectEqualDeep(
        OffsetValueResult{
            .remaining_input = " + (-1)",
            .offset_value = .{ .reference = .{ .AP, 0, false } },
        },
        try noInnerDereference("ap - 0 + (-1)"),
    );
}

test "parseValue: with inner dereference" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .FP, -1, true } },
            .offset2 = .{ .value = 2 },
            .dereference = true,
            .value_type = "felt",
        },
        try parseValue("[cast([fp + (-1)] + 2, felt*)]", std.testing.allocator),
    );
}

test "parseValue: with no inner dereference" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 2, false } },
            .offset2 = .{ .value = 0 },
            .dereference = false,
            .value_type = "felt",
        },
        try parseValue("cast(ap + 2, felt*)", std.testing.allocator),
    );
}

test "parseValue: with no register" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .value = 825323 },
            .offset2 = .{ .value = 0 },
            .dereference = false,
            .value_type = "felt",
        },
        try parseValue("cast(825323, felt*)", std.testing.allocator),
    );
}

test "parseValue: with no inner dereference and two offsets" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 0, false } },
            .offset2 = .{ .value = -1 },
            .dereference = true,
            .value_type = "felt",
        },
        try parseValue("[cast(ap - 0 + (-1), felt*)]", std.testing.allocator),
    );
}

test "parseValue: with inner dereference and offset" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 0, true } },
            .offset2 = .{ .value = 1 },
            .dereference = true,
            .value_type = "__main__.felt",
        },
        try parseValue("[cast([ap] + 1, __main__.felt*)]", std.testing.allocator),
    );
}

test "parseValue: with inner dereference and immediate" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 0, true } },
            .offset2 = .{ .immediate = Felt252.one() },
            .dereference = true,
            .value_type = "felt",
        },
        try parseValue("[cast([ap] + 1, felt)]", std.testing.allocator),
    );
}

test "parseValue: with inner dereference to pointer" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 1, true } },
            .offset2 = .{ .value = 1 },
            .dereference = true,
            .value_type = "felt",
        },
        try parseValue("[cast([ap + 1] + 1, felt*)]", std.testing.allocator),
    );
}

test "parseValue: with 2 inner dereference" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 0, true } },
            .offset2 = .{ .reference = .{ .FP, 1, true } },
            .dereference = true,
            .value_type = "__main__.felt",
        },
        try parseValue("[cast([ap] + [fp + 1], __main__.felt*)]", std.testing.allocator),
    );
}

test "parseValue: with 2 inner dereferences" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 1, true } },
            .offset2 = .{ .reference = .{ .FP, 1, true } },
            .dereference = true,
            .value_type = "__main__.felt",
        },
        try parseValue("[cast([ap + 1] + [fp + 1], __main__.felt*)]", std.testing.allocator),
    );
}

test "parseValue: with no reference" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .immediate = Felt252.fromInt(u32, 825323) },
            .offset2 = .{ .immediate = Felt252.zero() },
            .dereference = false,
            .value_type = "felt",
        },
        try parseValue("cast(825323, felt)", std.testing.allocator),
    );
}

test "parseValue: with one reference" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 0, true } },
            .offset2 = .{ .value = 1 },
            .dereference = true,
            .value_type = "starkware.cairo.common.cairo_secp.ec.EcPoint",
        },
        try parseValue("[cast([ap] + 1, starkware.cairo.common.cairo_secp.ec.EcPoint*)]", std.testing.allocator),
    );
}

test "parseValue: with double reference" {
    const res = try parseValue("[cast([ap] + 1, starkware.cairo.common.cairo_secp.ec.EcPoint**)]", std.testing.allocator);

    defer std.testing.allocator.free(res.value_type);

    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 0, true } },
            .offset2 = .{ .value = 1 },
            .dereference = true,
            .value_type = "starkware.cairo.common.cairo_secp.ec.EcPoint*",
        },
        res,
    );
}

test "parseValue: to felt with double reference" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 0, true } },
            .offset2 = .{ .reference = .{ .AP, 0, true } },
            .dereference = true,
            .value_type = "felt",
        },
        try parseValue("[cast([ap] + [ap], felt)]", std.testing.allocator),
    );
}

test "parseValue: to felt with double reference and offset" {
    try expectEqualDeep(
        ValueAddress{
            .offset1 = .{ .reference = .{ .AP, 1, true } },
            .offset2 = .{ .reference = .{ .AP, 2, true } },
            .dereference = true,
            .value_type = "felt",
        },
        try parseValue("[cast([ap + 1] + [ap + 2], felt)]", std.testing.allocator),
    );
}
