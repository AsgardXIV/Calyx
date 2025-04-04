const std = @import("std");

pub const String = struct {
    pub fn getUtf8ByteSize(char: u8) u3 {
        return std.unicode.utf8ByteSequenceLength(char) catch 1;
    }

    pub fn toLowerCase(str: []u8) void {
        for (0..str.len) |i| {
            const byte_size = getUtf8ByteSize(str[i]);
            if (byte_size == 1) str[i] = std.ascii.toLower(str[i]);
        }
    }

    pub fn toUpperCase(str: []u8) void {
        for (0..str.len) |i| {
            const byte_size = getUtf8ByteSize(str[i]);
            if (byte_size == 1) str[i] = std.ascii.toUpper(str[i]);
        }
    }
};
