const std = @import("std");

pub const CategoryID = enum(u8) {
    const Self = @This();

    common = 0x00,
    bgcommon = 0x01,
    bg = 0x02,
    cut = 0x03,
    chara = 0x04,
    shader = 0x05,
    ui = 0x06,
    sound = 0x07,
    vfx = 0x08,
    ui_script = 0x09,
    exd = 0x0A,
    game_script = 0x0B,
    music = 0x0C,
    sqpack_test = 0x12,
    debug = 0x13,

    pub fn fromString(str: []const u8) ?Self {
        return std.meta.stringToEnum(Self, str);
    }

    pub fn toString(self: Self) []const u8 {
        return std.enums.tagName(Self, self).?;
    }
};

test "categoryId" {
    {
        const actual = CategoryID.fromString("chara");
        try std.testing.expectEqual(CategoryID.chara, actual);
    }

    {
        const actual = CategoryID.ui.toString();
        try std.testing.expectEqual("ui", actual);
    }

    {
        const actual = CategoryID.fromString("invalid");
        try std.testing.expectEqual(null, actual);
    }
}
