const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryId = @import("category_id.zig").CategoryId;
const RepositoryId = @import("repository_id.zig").RepositoryId;

const game = @import("../../game.zig");
const Platform = game.Platform;

const PackFileName = @This();

category_id: CategoryId,
repo_id: RepositoryId,
chunk_id: u8,
platform: Platform,
file_extension: Extension,
file_idx: ?u8,

pub fn fromPackFileString(file_name: []const u8) !PackFileName {
    var parts = std.mem.splitScalar(u8, file_name, '.');

    const bundle_str = parts.next() orelse return error.InvalidSqPackFilename; // Bundle is the first section and contains category, repo, and chunk
    const platform_str = parts.next() orelse return error.InvalidSqPackFilename; // Platform is the second section, it's a string which we parse in Platform
    const extension = parts.next() orelse return error.InvalidSqPackFilename; // Extension is the third section, which is a string. It's parsed as a FileExtension but has special handling for numbered dat files

    if (bundle_str.len != 6) {
        return error.InvalidSqPackFilename;
    }

    const category_str = bundle_str[0..2];
    const repo_str = bundle_str[2..4];
    const chunk_str = bundle_str[4..6];

    // Resolve the category ID
    const category_id_int = try std.fmt.parseInt(u8, category_str, 16);
    const category_id: CategoryId = @enumFromInt(category_id_int);

    // Resolve the repository ID
    const repo_id = RepositoryId.fromIntId(try std.fmt.parseInt(u8, repo_str, 16));

    // Chunk is just a number
    const chunk = try std.fmt.parseInt(u8, chunk_str, 16);

    // Resolve the platform
    const platform = Platform.fromPlatformString(platform_str) orelse return error.InvalidPlatform;

    // Resolve the file type, with special handling for dat files
    var file_index: ?u8 = null;
    const file_extension: ?Extension = Extension.fromExtensionString(extension) orelse blk: {
        if (std.mem.startsWith(u8, extension, Extension.dat.toExensionString())) {
            file_index = try std.fmt.parseInt(u8, extension[3..], 10);
            break :blk .dat;
        }
        break :blk null;
    };

    if (file_extension == null) {
        return error.UnknownFileType;
    }

    // Return the parsed file name
    return .{
        .category_id = category_id,
        .repo_id = repo_id,
        .chunk_id = chunk,
        .platform = platform,
        .file_extension = file_extension.?,
        .file_idx = file_index,
    };
}

pub fn buildSqPackFileName(
    allocator: Allocator,
    category_id: CategoryId,
    repo_id: RepositoryId,
    chunk_id: u8,
    platform: Platform,
    file_extension: Extension,
    file_idx: ?u8,
) ![]const u8 {
    const name = PackFileName{
        .category_id = category_id,
        .repo_id = repo_id,
        .chunk_id = chunk_id,
        .platform = platform,
        .file_extension = file_extension,
        .file_idx = file_idx,
    };

    return try name.toPackFileString(allocator);
}

pub fn toPackFileString(path: *const PackFileName, allocator: Allocator) ![]const u8 {
    // First we determine if there is a file index and we build the postfix for it
    var buf: [4]u8 = undefined;
    const file_idx_str = if (path.file_idx) |fid|
        try std.fmt.bufPrint(&buf, "{d}", .{fid})
    else
        "";

    // Then we just format the string
    const formatted = try std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}.{s}.{s}{s}", .{
        @intFromEnum(path.category_id),
        path.repo_id.toIntId(),
        path.chunk_id,
        path.platform.toPlatformString(),
        path.file_extension.toExensionString(),
        file_idx_str,
    });

    return formatted;
}

pub const Extension = enum {
    const Self = @This();

    index,
    index2,
    ver,
    dat, // Dat files are numbered

    pub fn fromExtensionString(str: []const u8) ?Self {
        return std.meta.stringToEnum(Self, str);
    }

    pub fn toExensionString(self: Self) []const u8 {
        return std.enums.tagName(Self, self).?;
    }
};

test "fromPackFileString" {
    {
        // Basic test without file index
        const expected = "040602.win32.index";
        const result = try buildSqPackFileName(
            std.testing.allocator,
            CategoryId.chara,
            RepositoryId.fromIntId(6),
            2,
            Platform.win32,
            Extension.index,
            null,
        );
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }

    {
        // Basic test without file index base repo
        const expected = "040002.win32.index";
        const result = try buildSqPackFileName(
            std.testing.allocator,
            CategoryId.chara,
            RepositoryId.Base,
            2,
            Platform.win32,
            Extension.index,
            null,
        );
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }

    {
        // Another basic test without file index, but as an index2
        const expected = "040602.win32.index2";
        const result = try buildSqPackFileName(
            std.testing.allocator,
            CategoryId.chara,
            RepositoryId.fromIntId(6),
            2,
            Platform.win32,
            Extension.index2,
            null,
        );
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }

    {
        // Test with dat file index
        const expected = "030103.ps5.dat0";
        const result = try buildSqPackFileName(
            std.testing.allocator,
            CategoryId.cut,
            RepositoryId.fromIntId(1),
            3,
            Platform.ps5,
            Extension.dat,
            0,
        );
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
}

test "parseSqPackFileName" {
    {
        // Basic test without file index
        const expected = PackFileName{
            .category_id = CategoryId.chara,
            .repo_id = RepositoryId.fromIntId(6),
            .chunk_id = 2,
            .platform = Platform.win32,
            .file_extension = Extension.index,
            .file_idx = null,
        };
        const result = try fromPackFileString("040602.win32.index");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Basic test with a file index
        const expected = PackFileName{
            .category_id = CategoryId.chara,
            .repo_id = RepositoryId.fromIntId(6),
            .chunk_id = 2,
            .platform = Platform.ps5,
            .file_extension = Extension.dat,
            .file_idx = 3,
        };
        const result = try fromPackFileString("040602.ps5.dat3");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Bundle section is too short
        const result = fromPackFileString("04060.ps5.dat3");
        const expected = error.InvalidSqPackFilename;
        try std.testing.expectError(expected, result);
    }

    {
        // Format is totally wrong
        const result = fromPackFileString("invalid");
        const expected = error.InvalidSqPackFilename;
        try std.testing.expectError(expected, result);
    }
}
