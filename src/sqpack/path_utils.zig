const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryID = @import("category_id.zig").CategoryID;
const FileType = @import("file_type.zig").FileType;
const Platform = @import("../common/platform.zig").Platform;

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
