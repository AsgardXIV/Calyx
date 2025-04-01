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

pub const PathUtils = struct {
    const BaseRepoId: u8 = 0;
    const BaseRepoName = "ffxiv";
    const ExPackRepoPrefix = "ex";

    pub fn buildSqPackFileName(
        allocator: Allocator,
        category_id: CategoryID,
        repo_id: u8,
        chunk_id: u8,
        platform: Platform,
        file_type: FileType,
        file_idx: ?u8,
    ) ![]const u8 {
        var buf: [4]u8 = undefined;
        const file_id_str = if (file_idx) |fid|
            try std.fmt.bufPrint(&buf, "{d}", .{fid})
        else
            "";

        const formatted = try std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}.{s}.{s}{s}", .{
            @intFromEnum(category_id),
            repo_id,
            chunk_id,
            platform.toString(),
            file_type.toString(),
            file_id_str,
        });

        return formatted;
    }

    pub fn repoNameToId(repo_name: []const u8, fallback: bool) !u8 {
        if (std.mem.eql(u8, repo_name, BaseRepoName)) {
            return BaseRepoId;
        } else if (std.mem.startsWith(u8, repo_name, ExPackRepoPrefix)) {
            return try std.fmt.parseInt(u8, repo_name[2..], 10);
        } else {
            if (!fallback) {
                return error.InvalidRepo;
            }
            return BaseRepoId;
        }
    }

    pub fn parseGamePath(path: []const u8) !ParsedGamePath {
        // Index 2 hash is easy
        const index2_hash = std.hash.Crc32.hash(path);

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
        const file_only_hash = std.hash.Crc32.hash(file_only_str);
        const directory_str = path[0 .. last_path_part + 1];
        const directory_hash = std.hash.Crc32.hash(directory_str);

        // Pack index1 hash
        const index1_hash: u64 = (@as(u64, @intCast(directory_hash)) << 32) | file_only_hash;

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

test "repoNameToId" {
    {
        const expected = PathUtils.BaseRepoId;
        const result = try PathUtils.repoNameToId(PathUtils.BaseRepoName, false);
        try std.testing.expectEqual(expected, result);
    }

    {
        const expected: u8 = 1;
        const result = try PathUtils.repoNameToId("ex1", false);
        try std.testing.expectEqual(expected, result);
    }

    {
        const expected: u8 = 9;
        const result = try PathUtils.repoNameToId("ex9", false);
        try std.testing.expectEqual(expected, result);
    }

    {
        const expected = error.InvalidRepo;
        const result = PathUtils.repoNameToId("beep", false);
        try std.testing.expectError(expected, result);
    }

    {
        const expected: u8 = 0;
        const result = try PathUtils.repoNameToId("beep", true);
        try std.testing.expectEqual(expected, result);
    }
}

test "calculateGamePath" {
    {
        const expected = ParsedGamePath{
            .category_id = CategoryID.chara,
            .repo_id = 6,
            .index1_hash = 0xadb96341ab3431f9,
            .index2_hash = 0x412fbc68,
        };
        const result = try PathUtils.parseGamePath("chara/ex6/beep.dat");
        try std.testing.expectEqual(expected, result);
    }

    {
        const expected = ParsedGamePath{
            .category_id = CategoryID.chara,
            .repo_id = 0,
            .index1_hash = 0x9538ab3cab3431f9,
            .index2_hash = 0xcd35ddff,
        };
        const result = try PathUtils.parseGamePath("chara/beep.dat");
        try std.testing.expectEqual(expected, result);
    }

    {
        const expected = error.MalformedPath;
        const result = PathUtils.parseGamePath("chara");
        try std.testing.expectError(expected, result);
    }

    {
        const expected = error.InvalidCategory;
        const result = PathUtils.parseGamePath("beep/ex6/test.dat");
        try std.testing.expectError(expected, result);
    }

    {
        const expected = ParsedGamePath{
            .category_id = CategoryID.chara,
            .repo_id = 6,
            .index1_hash = 0x5220665400000000,
            .index2_hash = 0x52206654,
        };
        const result = try PathUtils.parseGamePath("chara/ex6/folder/");
        try std.testing.expectEqual(expected, result);
    }
}
