const std = @import("std");

pub const Platform = enum(u8) {
    const XboxCodeName = "lys";
    const Self = @This();

    win32 = 0x00,
    ps3 = 0x01,
    ps4 = 0x02,
    ps5 = 0x03,
    xbox = 0x04, // lys

    pub fn fromPlatformString(str: []const u8) ?Self {
        if (std.mem.eql(u8, str, XboxCodeName)) return .xbox;

        return std.meta.stringToEnum(Self, str);
    }

    pub fn toPlatformString(self: Self) []const u8 {
        return switch (self) {
            .xbox => XboxCodeName,
            else => std.enums.tagName(Self, self).?,
        };
    }
};

test "basic fromPlatformString" {
    const platform = Platform.fromPlatformString("win32");
    try std.testing.expectEqual(Platform.win32, platform);
}

test "basic toPlatformString" {
    const platform = Platform.win32;
    const id = platform.toPlatformString();
    try std.testing.expectEqual("win32", id);
}

test "xbox fromPlatformString" {
    {
        const platform = Platform.fromPlatformString("lys");
        try std.testing.expectEqual(Platform.xbox, platform);
    }

    {
        const platform = Platform.fromPlatformString("xbox");
        try std.testing.expectEqual(Platform.xbox, platform);
    }
}

test "xbox toPlatformString" {
    const platform = Platform.xbox;
    const id = platform.toPlatformString();
    try std.testing.expectEqual("lys", id);
}
