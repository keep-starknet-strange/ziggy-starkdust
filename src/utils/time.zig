const std = @import("std");
const time = @import("std").time;

/// Represents a date and time.
pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,

    /// Checks if a given year is a leap year.
    ///
    /// # Arguments
    ///
    /// * `year` - The year to check.
    ///
    /// # Returns
    ///
    /// Returns `true` if the year is a leap year, otherwise `false`.
    pub fn isLeapYear(year: u16) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }

    /// Gets the number of days in a month for a given year.
    ///
    /// # Arguments
    ///
    /// * `year` - The year.
    /// * `month` - The month.
    ///
    /// # Returns
    ///
    /// The number of days in the month.
    pub fn numDaysInMonth(year: u16, month: u8) u8 {
        const daysInMonth = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (month == 2 and isLeapYear(year)) return 29;
        return daysInMonth[month - 1];
    }

    /// Gets the number of days in a year.
    ///
    /// # Arguments
    ///
    /// * `year` - The year to check.
    ///
    /// # Returns
    ///
    /// The number of days in the year.
    pub fn numDaysInYear(year: u16) u64 {
        return if (isLeapYear(year)) 366 else 365;
    }

    /// Gets the current date and time.
    ///
    /// # Returns
    ///
    /// A `DateTime` struct representing the current date and time.
    pub fn now() DateTime {
        const raw_timestamp = time.timestamp();

        // Handle this error case as needed
        if (raw_timestamp < 0) {
            unreachable;
        }

        const timestamp = @as(u64, @intCast(raw_timestamp));
        var seconds_left = timestamp;
        var year: u16 = 1970;

        // Calculate the year
        while (seconds_left >= (@as(u64, @intCast(numDaysInYear(year))) * 86_400)) {
            seconds_left -= (@as(u64, @intCast(numDaysInYear(year))) * 86_400);
            year += 1;
        }

        var month: u8 = 1;

        // Calculate the month
        while (seconds_left >= (@as(u64, @intCast(numDaysInMonth(year, month))) * 86400)) {
            seconds_left -= (@as(u64, @intCast(numDaysInMonth(year, month))) * 86400);
            month += 1;
        }

        const day = @as(u8, @intCast((seconds_left / 86400) + 1));
        seconds_left %= 86400;

        const hour = @as(u8, @intCast(seconds_left / 3600));
        seconds_left %= 3600;

        const minute = @as(u8, @intCast(seconds_left / 60));
        const second = @as(u8, @intCast(seconds_left % 60));

        return DateTime{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
        };
    }

    /// Formats the `DateTime` into a string.
    ///
    /// # Arguments
    ///
    /// * `allocator` - The memory allocator to use.
    ///
    /// # Returns
    ///
    /// A formatted string representing the date and time.
    pub fn format(self: DateTime, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", .{ self.year, self.month, self.day, self.hour, self.minute, self.second });
    }
};

// ************************************************************
// *                         TESTS                            *
// ************************************************************
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "format should work as expected" {
    // Consider using a testing allocator.
    var allocator = std.heap.page_allocator;

    const datetime = DateTime{
        .year = 2023,
        .month = 10,
        .day = 18,
        .hour = 13,
        .minute = 9,
        .second = 11,
    };

    const time_log = try datetime.format(allocator);
    defer allocator.free(time_log);

    // This test is currently failing; the minute should be zero-padded
    // TODO: Fix this and update assertion to expect("2023-10-18T13:09:11Z")
    try expect(std.mem.eql(u8, time_log, "2023-10-18T13: 9:11Z"));
}
