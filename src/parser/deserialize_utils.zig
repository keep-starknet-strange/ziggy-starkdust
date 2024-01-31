const std = @import("std");
const Register = @import("../vm/instructions.zig").Register;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Represents the error that can occur during deserialization
pub const DeserializationError = error{CastDeserialization};

/// Represents the result of parsing brackets within a byte array.
pub const ParseOptResult = std.meta.Tuple(&.{ []const u8, bool });

/// Represents the result of parsing the first argument of a 'cast' expression.
pub const CastArgs = std.meta.Tuple(&.{ []const u8, []const u8 });

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
        return .{ input, false };

    // Refine the check to ensure that the match is the beginning and end of the string
    if (std.mem.eql(u8, it_in.first(), "") and std.mem.eql(u8, it_out.first(), "")) {
        // Return a tuple containing the content within the outer brackets and true
        return .{ input[it_in.index.?..it_out.index.?], true };
    }

    // If the above conditions are not met, return the original input with a false boolean value
    return .{ input, false };
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
        std.mem.trim(u8, it.first(), " "),
        std.mem.trim(u8, it.rest(), " "),
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
pub fn parseOffset(input: []const u8) !i32 {
    // Check for empty input
    if (std.mem.eql(u8, input, "")) {
        return 0;
    }

    var sign: i32 = 1;
    var index_after_sign: usize = 0;

    // Iterate over the input to find the end of whitespaces and determine the sign
    for (input, 0..) |c, i| {
        // Searching end of whitespaces
        if (c != 32) {
            // Modify index after the sign
            index_after_sign = i + 1;
            // Minus sign (no change for plus sign)
            if (c == 45) sign = -1;
            break;
        }
    }

    // Extract content without the sign
    const without_sign = std.mem.trim(u8, input[index_after_sign..], " ");
    // Trim parentheses from both sides
    const without_parenthesis = std.mem.trimRight(
        u8,
        std.mem.trimLeft(u8, without_sign, "("),
        ")",
    );

    // Parse the offset and apply the sign
    return sign * try std.fmt.parseInt(i32, without_parenthesis, 10);
}

/// Parses a register from a byte array.
///
/// This function takes a byte array `input` and attempts to identify and parse a register
/// representation within it. It recognizes registers such as "ap" and "fp". If a valid register
/// is found, it returns the corresponding `Register` enum variant; otherwise, it returns `null`.
///
/// # Parameters
/// - `input`: A byte array where a register needs to be parsed.
///
/// # Returns
/// A `Register` enum variant if a valid register is found; otherwise, returns `null`.
pub fn parseRegister(input: []const u8) ?Register {
    // Check for the presence of "ap" in the input
    if (std.mem.indexOf(u8, input, "ap")) |_| return .AP;

    // Check for the presence of "fp" in the input
    if (std.mem.indexOf(u8, input, "fp")) |_| return .FP;

    // If no valid register is found, return `null`
    return null;
}

test "outerBrackets: should check if the input has outer brackets" {
    // Test case where input has both outer brackets '[...]' and nested brackets '(...)'
    const deref_value = outerBrackets("[cast([fp])]");

    // Check if the content within the outer brackets is extracted correctly
    try expectEqualStrings("cast([fp])", deref_value[0]);

    // Check if the boolean indicating successful parsing is true
    try expect(deref_value[1]);

    // Test case where input has nested brackets but no outer brackets
    const ref_value = outerBrackets("cast([fp])");

    // Check if the function returns the input itself as no outer brackets are present
    try expectEqualStrings("cast([fp])", ref_value[0]);

    // Check if the boolean indicating successful parsing is false
    try expect(!ref_value[1]);

    // Test case where input is an empty string
    const empty_value = outerBrackets("");

    // Check if the function returns an empty string as there are no brackets
    try expectEqualStrings("", empty_value[0]);

    // Check if the boolean indicating successful parsing is false for an empty string
    try expect(!empty_value[1]);

    // Test case where input contains only empty brackets '[]'
    const only_brackets_value = outerBrackets("[]");

    // Check if the function returns an empty string as there is nothing inside the brackets
    try expectEqualStrings("", only_brackets_value[0]);

    // Check if the boolean indicating successful parsing is true for empty brackets
    try expect(only_brackets_value[1]);
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
    const res = try takeCastFirstArg("cast([fp + (-1)], felt*)");

    // Check if the first argument is extracted correctly.
    try expectEqualStrings(
        "[fp + (-1)]",
        res[0],
    );

    // Check if the second argument is extracted correctly.
    try expectEqualStrings(
        "felt*",
        res[1],
    );

    // Test case 2: Valid 'cast' expression with complex expressions as arguments.
    const res1 = try takeCastFirstArg("cast(([ap + (-53)] + [ap + (-52)] + [ap + (-51)] - [[ap + (-43)] + 68]) * (-1809251394333065606848661391547535052811553607665798349986546028067936010240), felt)");

    // Check if the first argument is extracted correctly.
    try expectEqualStrings(
        "([ap + (-53)] + [ap + (-52)] + [ap + (-51)] - [[ap + (-43)] + 68]) * (-1809251394333065606848661391547535052811553607665798349986546028067936010240)",
        res1[0],
    );

    // Check if the second argument is extracted correctly.
    try expectEqualStrings(
        "felt",
        res1[1],
    );

    // Test case 3: Invalid 'cast' expression with insufficient arguments.
    try expectError(
        DeserializationError.CastDeserialization,
        takeCastFirstArg("n"),
    );
}

test "parseOffset: should correctly parse positive and negative offsets" {
    // Test case: Should correctly parse a negative offset with parentheses
    try expectEqual(@as(i32, -1), try parseOffset(" + (-1)"));

    // Test case: Should correctly parse a positive offset
    try expectEqual(@as(i32, 1), try parseOffset(" + 1"));

    // Test case: Should correctly parse a negative offset without parentheses
    try expectEqual(@as(i32, -1), try parseOffset(" - 1"));

    // Test case: Should handle an empty input, resulting in offset 0
    try expectEqual(@as(i32, 0), try parseOffset(""));

    // Test case: Should correctly parse a negative offset with a leading plus sign
    try expectEqual(@as(i32, -3), try parseOffset("+ (-3)"));
}

test "parseRegister: should correctly identify and parse registers" {
    // Test case: Register "fp" is present in the input
    try expectEqual(Register.FP, parseRegister("fp + (-1)"));

    // Test case: Register "ap" is present in the input
    try expectEqual(Register.AP, parseRegister("ap + (-1)"));

    // Test case: Register "fp" is present in the input with a different offset
    try expectEqual(Register.FP, parseRegister("fp + (-3)"));

    // Test case: Register "ap" is present in the input with a different offset
    try expectEqual(Register.AP, parseRegister("ap + (-9)"));
}
