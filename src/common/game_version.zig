const std = @import("std");

pub const GameVersion = struct {
    pub const unknown = unknownVersion();

    const version_str_len = 20;

    str: [version_str_len]u8,
    year: u16,
    month: u16,
    day: u16,
    build: u16,
    revision: u16,
    valid: bool,

    pub fn parseFromString(version_str: []const u8) !GameVersion {
        var self: GameVersion = undefined;

        // Handle string first
        if (version_str.len != version_str_len) {
            return error.InvalidVersionString;
        }

        @memcpy(self.str[0..version_str_len], version_str);

        // Break it down into parts
        var parts = std.mem.splitSequence(u8, version_str, ".");
        const year_str = parts.next() orelse return error.InvalidVersionString;
        const month_str = parts.next() orelse return error.InvalidVersionString;
        const day_str = parts.next() orelse return error.InvalidVersionString;
        const build_str = parts.next() orelse return error.InvalidVersionString;
        const revision_str = parts.next() orelse return error.InvalidVersionString;

        self.year = try std.fmt.parseInt(u16, year_str, 10);
        self.month = try std.fmt.parseInt(u16, month_str, 10);
        self.day = try std.fmt.parseInt(u16, day_str, 10);
        self.build = try std.fmt.parseInt(u16, build_str, 10);
        self.revision = try std.fmt.parseInt(u16, revision_str, 10);
        self.valid = true;

        return self;
    }

    pub fn parseFromFile(file: *const std.fs.File) !GameVersion {
        var version_str: [version_str_len]u8 = undefined;
        _ = try file.readAll(&version_str);
        return try GameVersion.parseFromString(&version_str);
    }

    pub fn parseFromFilePath(file_path: []const u8) !GameVersion {
        const file = try std.fs.openFileAbsolute(file_path, .{ .mode = .read_only });
        errdefer file.close();
        return try GameVersion.parseFromFile(&file);
    }

    pub fn versionString(self: *const GameVersion) []const u8 {
        return &self.str;
    }

    pub fn isNewerThan(self: GameVersion, other: GameVersion) bool {
        if (self.year > other.year) return true;
        if (self.year < other.year) return false;

        if (self.month > other.month) return true;
        if (self.month < other.month) return false;

        if (self.day > other.day) return true;
        if (self.day < other.day) return false;

        if (self.build > other.build) return true;
        if (self.build < other.build) return false;

        if (self.revision > other.revision) return true;
        return false;
    }

    fn unknownVersion() GameVersion {
        const unknown_str = "0000.00.00.0000.0000";

        var version = GameVersion{
            .str = undefined,
            .year = 0,
            .month = 0,
            .day = 0,
            .build = 0,
            .revision = 0,
            .valid = false,
        };

        @memcpy(version.str[0..unknown_str.len], unknown_str);

        return version;
    }
};

test "GameVersion.parseFromString" {
    {
        const input = "2025.03.27.0100.1337";
        const version = try GameVersion.parseFromString(input);

        var expected: GameVersion = undefined;
        @memcpy(expected.str[0..20], "2025.03.27.0100.1337");
        expected.year = 2025;
        expected.month = 3;
        expected.day = 27;
        expected.build = 100;
        expected.revision = 1337;
        expected.valid = true;
        try std.testing.expectEqual(expected, version);
    }

    {
        const input = "blahblah";
        const err = GameVersion.parseFromString(input);
        try std.testing.expectError(error.InvalidVersionString, err);
    }
}

test "GameVersion.isNewerThan" {
    const version1 = try GameVersion.parseFromString("2025.03.27.0100.1337");
    const version2 = try GameVersion.parseFromString("2025.03.27.0100.1338");
    const version3 = try GameVersion.parseFromString("2025.03.27.0100.1336");

    try std.testing.expectEqual(true, version1.isNewerThan(version3));
    try std.testing.expectEqual(false, version1.isNewerThan(version2));
    try std.testing.expectEqual(false, version1.isNewerThan(version1));
}
