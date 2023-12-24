const std = @import("std");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Represents the result of parsing brackets within a byte array.
pub const ParseOptResult = std.meta.Tuple(&.{ []const u8, bool });

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

    // Check if the first element after splitting at '[' and ']' is an empty string
    if (std.mem.eql(u8, it_in.first(), "") and std.mem.eql(u8, it_out.first(), "")) {
        // Check if both 'it_in' and 'it_out' indices are not null
        if (it_in.index != null and it_out.index != null) {
            // Return a tuple containing the content within the outer brackets and true
            return .{ input[it_in.index.?..it_out.index.?], true };
        }
    }

    // Return the original input and a false boolean value indicating unsuccessful parsing
    return .{ input, false };
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
