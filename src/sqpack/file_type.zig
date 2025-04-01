const std = @import("std");

pub const FileType = enum {
    const Self = @This();

    index,
    index2,
    ver,
    dat,

    pub fn fromString(str: []const u8) ?Self {
        return std.meta.stringToEnum(Self, str);
    }

    pub fn toString(self: Self) []const u8 {
        return std.enums.tagName(Self, self).?;
    }
};
