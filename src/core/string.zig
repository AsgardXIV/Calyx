const std = @import("std");

pub const String = struct {
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
};
