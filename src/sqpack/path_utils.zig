const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryID = @import("category_id.zig").CategoryID;
const FileType = @import("file_type.zig").FileType;
const Platform = @import("../common/platform.zig").Platform;

pub const ParsedGamePath = struct {
    category_id: CategoryID,
    repo_id: u8,
    index1_hash: u64,
    index2_hash: u32,
};

pub const ParsedSqPackFileName = struct {
    category_id: CategoryID,
    repo_id: u8,
    chunk_id: u8,
    platform: Platform,
    file_type: FileType,
    file_idx: ?u8,
};

pub const FileLookupResult = struct {
    data_file_id: u8,
    data_file_offset: u64,
    repo_id: u8,
    category_id: CategoryID,
    chunk_id: u8,
};

pub const PathUtils = struct {
    const BaseRepoId: u8 = 0;
    const BaseRepoName = "ffxiv";
    const ExPackRepoPrefix = "ex";

    pub fn crc32(data: []const u8) u32 {
        return std.hash.crc.Crc32Jamcrc.hash(data);
    }

    pub fn buildSqPackFileName(
        allocator: Allocator,
        category_id: CategoryID,
        repo_id: u8,
        chunk_id: u8,
        platform: Platform,
        file_type: FileType,
        file_idx: ?u8,
    ) ![]const u8 {
        return try buildSqPackFileNameTyped(
            allocator,
            .{
                .category_id = category_id,
                .repo_id = repo_id,
                .chunk_id = chunk_id,
                .platform = platform,
                .file_type = file_type,
                .file_idx = file_idx,
            },
        );
    }

    pub fn buildSqPackFileNameTyped(
        allocator: Allocator,
        path: ParsedSqPackFileName,
    ) ![]const u8 {

        // First we determine if there is a file index and we build the postfix for it
        var buf: [4]u8 = undefined;
        const file_idx_str = if (path.file_idx) |fid|
            try std.fmt.bufPrint(&buf, "{d}", .{fid})
        else
            "";

        // Then we just format the string
        const formatted = try std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}.{s}.{s}{s}", .{
            @intFromEnum(path.category_id),
            path.repo_id,
            path.chunk_id,
            path.platform.toString(),
            path.file_type.toString(),
            file_idx_str,
        });

        return formatted;
    }

    pub fn parseSqPackFileName(file_name: []const u8) !ParsedSqPackFileName {
        var parts = std.mem.splitSequence(u8, file_name, ".");

        const bundle_str = parts.next() orelse return error.InvalidSqPackFilename; // Bundle is the first section and contains category, repo, and chunk
        const platform_str = parts.next() orelse return error.InvalidSqPackFilename; // Platform is the second section, it's a string which we parse in Platform
        const extension = parts.next() orelse return error.InvalidSqPackFilename; // Extension is the third section, which is a string. It's parsed as a FileType but has special handling for numbered dat files

        if (bundle_str.len != 6) {
            return error.InvalidSqPackFilename;
        }

        const category_str = bundle_str[0..2];
        const repo_str = bundle_str[2..4];
        const chunk_str = bundle_str[4..6];

        // Resolve the category ID
        const category_id_int = try std.fmt.parseInt(u8, category_str, 16);
        const category_id: CategoryID = @enumFromInt(category_id_int);

        // Resolve the repository ID
        const repo_id = try std.fmt.parseInt(u8, repo_str, 16);

        // Chunk is just a number
        const chunk = try std.fmt.parseInt(u8, chunk_str, 16);

        // Resolve the platform
        const platform = Platform.fromString(platform_str) orelse return error.InvalidPlatform;

        // Resolve the file type, with special handling for dat files
        var file_index: ?u8 = null;
        const file_type: ?FileType = FileType.fromString(extension) orelse blk: {
            if (std.mem.startsWith(u8, extension, FileType.dat.toString())) {
                file_index = try std.fmt.parseInt(u8, extension[3..], 10);
                break :blk .dat;
            }
            break :blk null;
        };

        if (file_type == null) {
            return error.InvalidFileType;
        }

        // Return the parsed file name
        return ParsedSqPackFileName{
            .category_id = category_id,
            .repo_id = repo_id,
            .chunk_id = chunk,
            .platform = platform,
            .file_type = file_type.?,
            .file_idx = file_index,
        };
    }

    pub fn repoNameToId(repo_name: []const u8, fallback: bool) !u8 {
        if (std.mem.eql(u8, repo_name, BaseRepoName)) {
            // Explicitly base repo
            return BaseRepoId;
        } else if (std.mem.startsWith(u8, repo_name, ExPackRepoPrefix)) {
            // Expansion pack
            return try std.fmt.parseInt(u8, repo_name[2..], 10);
        } else {
            if (!fallback) {
                // If not explicitly base repo and not expansion pack, and no base fallback, return error
                return error.InvalidRepo;
            }

            // If not explicitly base repo and not expansion pack, but fallback is allowed, return base repo ID
            return BaseRepoId;
        }
    }

    pub fn parseGamePath(path: []const u8) !ParsedGamePath {
        // Index 2 hash is easy
        const index2_hash = crc32(path);

        // Split the path into parts
        var path_parts = std.mem.splitAny(u8, path, "/");

        // Get the category ID
        const category_name = path_parts.next() orelse return error.MalformedPath;
        const category_id = CategoryID.fromString(category_name) orelse return error.InvalidCategory;

        // Get the repository ID
        const repo_name = path_parts.next() orelse return error.MalformedPath;
        const repo_id = try repoNameToId(repo_name, true);

        // Split what we need for index1
        const last_path_part = std.mem.lastIndexOf(u8, path, "/") orelse return error.InvalidPath;
        const file_only_str = path[last_path_part + 1 ..];
        const file_only_hash = crc32(file_only_str);
        const directory_str = path[0..last_path_part];
        const directory_hash = crc32(directory_str);

        // Pack index1 hash
        const index1_hash: u64 = (@as(u64, directory_hash) << 32) | file_only_hash;

        return ParsedGamePath{
            .category_id = category_id,
            .repo_id = repo_id,
            .index1_hash = index1_hash,
            .index2_hash = index2_hash,
        };
    }
};

test "buildSqPackFileName" {
    {
        // Basic test without file index
        const expected = "040602.win32.index";
        const result = try PathUtils.buildSqPackFileName(
            std.testing.allocator,
            CategoryID.chara,
            6,
            2,
            Platform.win32,
            FileType.index,
            null,
        );
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }

    {
        // Another basic test without file index, but as an index2
        const expected = "040602.win32.index2";
        const result = try PathUtils.buildSqPackFileName(
            std.testing.allocator,
            CategoryID.chara,
            6,
            2,
            Platform.win32,
            FileType.index2,
            null,
        );
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }

    {
        // Test with dat file index
        const expected = "030103.ps5.dat0";
        const result = try PathUtils.buildSqPackFileName(
            std.testing.allocator,
            CategoryID.cut,
            1,
            3,
            Platform.ps5,
            FileType.dat,
            0,
        );
        defer std.testing.allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
}

test "crc32" {
    {
        const expected = 0xa2850653;
        const result = PathUtils.crc32("chara/equipment/e0633/material/v0010/mt_c0101e0633_met_a.mtrl");
        try std.testing.expectEqual(expected, result);
    }
}

test "parseSqPackFileName" {
    {
        // Basic test without file index
        const expected = ParsedSqPackFileName{
            .category_id = CategoryID.chara,
            .repo_id = 6,
            .chunk_id = 2,
            .platform = Platform.win32,
            .file_type = FileType.index,
            .file_idx = null,
        };
        const result = try PathUtils.parseSqPackFileName("040602.win32.index");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Basic test with a file index
        const expected = ParsedSqPackFileName{
            .category_id = CategoryID.chara,
            .repo_id = 6,
            .chunk_id = 2,
            .platform = Platform.ps5,
            .file_type = FileType.dat,
            .file_idx = 3,
        };
        const result = try PathUtils.parseSqPackFileName("040602.ps5.dat3");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Bundle section is too short
        const result = PathUtils.parseSqPackFileName("04060.ps5.dat3");
        const expected = error.InvalidSqPackFilename;
        try std.testing.expectError(expected, result);
    }

    {
        // Format is totally wrong
        const result = PathUtils.parseSqPackFileName("invalid");
        const expected = error.InvalidSqPackFilename;
        try std.testing.expectError(expected, result);
    }
}

test "repoNameToId" {
    {
        // Resolve base repo name
        const expected = PathUtils.BaseRepoId;
        const result = try PathUtils.repoNameToId(PathUtils.BaseRepoName, false);
        try std.testing.expectEqual(expected, result);
    }

    {
        // Resolve expansion pack repo name
        const expected: u8 = 1;
        const result = try PathUtils.repoNameToId("ex1", false);
        try std.testing.expectEqual(expected, result);
    }

    {
        // Another expansion pack repo name
        const expected: u8 = 9;
        const result = try PathUtils.repoNameToId("ex9", false);
        try std.testing.expectEqual(expected, result);
    }

    {
        // Invalid repo name, no fallback so error
        const expected = error.InvalidRepo;
        const result = PathUtils.repoNameToId("beep", false);
        try std.testing.expectError(expected, result);
    }

    {
        // Invalid repo name, but fallback is allowed so base repo ID is returned
        const expected: u8 = 0;
        const result = try PathUtils.repoNameToId("beep", true);
        try std.testing.expectEqual(expected, result);
    }
}

test "parseGamePath" {
    {
        // Basic path with explicit repo ID
        const expected = ParsedGamePath{
            .category_id = CategoryID.chara,
            .repo_id = 6,
            .index1_hash = 0x2e7e889c54cbce06,
            .index2_hash = 0xbed04397,
        };
        const result = try PathUtils.parseGamePath("chara/ex6/beep.dat");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Basic path with implicit repo ID

        const expected = ParsedGamePath{
            .category_id = CategoryID.chara,
            .repo_id = 0,
            .index1_hash = 0x7774313e54cbce06,
            .index2_hash = 0x32ca2200,
        };
        const result = try PathUtils.parseGamePath("chara/beep.dat");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Invalid path, too short
        const expected = error.MalformedPath;
        const result = PathUtils.parseGamePath("chara");
        try std.testing.expectError(expected, result);
    }

    {
        // Invalid category ID
        const expected = error.InvalidCategory;
        const result = PathUtils.parseGamePath("beep/ex6/test.dat");
        try std.testing.expectError(expected, result);
    }

    {
        // Blank file name, technically allowed
        const expected = ParsedGamePath{
            .category_id = CategoryID.chara,
            .repo_id = 6,
            .index1_hash = 0xb811ed45ffffffff,
            .index2_hash = 0xaddf99ab,
        };
        const result = try PathUtils.parseGamePath("chara/ex6/folder/");
        try std.testing.expectEqual(expected, result);
    }
}
