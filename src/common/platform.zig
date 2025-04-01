const std = @import("std");

pub const Platform = enum(u8) {
    const Self = @This();

    win32 = 0x00,
    ps3 = 0x01,
    ps4 = 0x02,
    ps5 = 0x03,
    lys = 0x04, // xbox

    pub fn fromString(str: []const u8) ?Self {
        return std.meta.stringToEnum(Self, str);
    }

    pub fn toString(self: Self) []const u8 {
        return std.enums.tagName(Self, self).?;
    }
};
