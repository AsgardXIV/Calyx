const std = @import("std");

pub const Language = enum(u8) {
    none = 0x0,
    japanese = 0x1,
    english = 0x2,
    german = 0x3,
    french = 0x4,
    chinese_simplified = 0x5,
    chinese_traditional = 0x6,
    korean = 0x7,

    pub fn toLanguageString(self: Language) []const u8 {
        return switch (self) {
            .none => "",
            .japanese => "ja",
            .english => "en",
            .german => "de",
            .french => "fr",
            .chinese_simplified => "chs",
            .chinese_traditional => "cht",
            .korean => "ko",
        };
    }
};

test "basic toLanguageString" {
    const language = Language.english;
    const id = language.toLanguageString();
    try std.testing.expectEqual("en", id);
}
