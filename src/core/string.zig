const std = @import("std");

pub fn getUtf8ByteSize(char: u8) u3 {
    return std.unicode.utf8ByteSequenceLength(char) catch 1;
}

pub fn toLowerCase(str: []u8) void {
    var i: usize = 0;
    while (i < str.len) {
        const size = getUtf8ByteSize(str[i]);
        if (size == 1) str[i] = std.ascii.toLower(str[i]);
        i += size;
    }
}

pub fn toUpperCase(str: []u8) void {
    var i: usize = 0;
    while (i < str.len) {
        const size = getUtf8ByteSize(str[i]);
        if (size == 1) str[i] = std.ascii.toUpper(str[i]);
        i += size;
    }
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
