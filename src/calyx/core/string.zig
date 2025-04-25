const std = @import("std");

/// Determines the number of bytes needed to represent a UTF-8 character given its first byte.
///
/// `char` is the first byte of the UTF-8 character.
///
/// Returns the number of bytes needed to represent the character or 1 if the character is not valid UTF-8.
pub fn getUtf8ByteSize(char: u8) u3 {
    return std.unicode.utf8ByteSequenceLength(char) catch 1;
}

/// Converts `str` to lowercase in place.
///
/// Only ASCII characters are converted to lowercase.
pub fn toLowerCase(str: []u8) void {
    var i: usize = 0;
    while (i < str.len) {
        const size = getUtf8ByteSize(str[i]);
        if (size == 1) str[i] = std.ascii.toLower(str[i]);
        i += size;
    }
}

/// Allocates a new string and converts `str` to lowercase.
///
/// Only ASCII characters are converted to lowercase.
///
/// The new string is allocated using the provided allocator.
/// The caller is responsible for freeing the returned string.
pub fn allocToLowerCase(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    const result = try allocator.dupe(u8, str);
    toLowerCase(result);
    return result;
}

/// Converts `str` to uppercase in place.
///
/// Only ASCII characters are converted to uppercase.
pub fn toUpperCase(str: []u8) void {
    var i: usize = 0;
    while (i < str.len) {
        const size = getUtf8ByteSize(str[i]);
        if (size == 1) str[i] = std.ascii.toUpper(str[i]);
        i += size;
    }
}

/// Allocates a new string and converts `str` to uppercase.
///
/// Only ASCII characters are converted to uppercase.
///
/// The new string is allocated using the provided allocator.
/// The caller is responsible for freeing the returned string.
pub fn allocToUpperCase(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    const result = try allocator.dupe(u8, str);
    toUpperCase(result);
    return result;
}

test "getUtf8ByteSize works for ASCII" {
    try std.testing.expect(getUtf8ByteSize('a') == 1);
    try std.testing.expect(getUtf8ByteSize('b') == 1);
}

test "getUtf8ByteSize works for non-ASCII" {
    const euro = "€";
    const first_byte = euro[0];
    try std.testing.expect(getUtf8ByteSize(first_byte) == 3);
}

test "getUtf8ByteSize works with invalid byte sequences" {
    try std.testing.expect(getUtf8ByteSize(0x80) == 1); // The 0x80 byte is invalid by itself
}

test "toLowerCase converts ASCII only" {
    var buf = [_]u8{ 'H', 'E', 'L', 'L', 'O', ' ', 'W', 'O', 'R', 'L', 'D' };
    toLowerCase(&buf);
    try std.testing.expectEqualStrings("hello world", &buf);
}

test "toUpperCase converts ASCII only" {
    var buf = [_]u8{ 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd' };
    toUpperCase(&buf);
    try std.testing.expectEqualStrings("HELLO WORLD", &buf);
}

test "toLowerCase ignores UTF-8 multi-byte chars" {
    var buf = [_]u8{ 0xC3, 0x89, ' ', 'T', 'E', 'S', 'T' }; // É TEST
    toLowerCase(&buf);
    try std.testing.expectEqualStrings("\xC3\x89 test", &buf);
}

test "toUpperCase ignores UTF-8 multi-byte chars" {
    var buf = [_]u8{ 0xC3, 0xA9, ' ', 't', 'e', 's', 't' }; // é test
    toUpperCase(&buf);
    try std.testing.expectEqualStrings("\xC3\xA9 TEST", &buf);
}

test "allocToLowerCase basic" {
    const input = "HELLO WORLD";

    const result = try allocToLowerCase(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "allocToUpperCase basic" {
    const input = "hello world";

    const result = try allocToUpperCase(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("HELLO WORLD", result);
}
