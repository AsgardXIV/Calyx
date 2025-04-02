const std = @import("std");

const Allocator = std.mem.Allocator;

pub const RepositoryId = struct {
    const BaseRepoId: u8 = 0;
    const BaseRepoName = "ffxiv";
    const ExPackRepoPrefix = "ex";

    const base = RepositoryId{
        .id = BaseRepoId,
    };

    id: u8,

    pub fn toString(self: RepositoryId, allocator: Allocator) ![]const u8 {
        if (self.id == BaseRepoId) {
            return try std.fmt.allocPrint(allocator, "{s}", .{BaseRepoName});
        } else {
            return try std.fmt.allocPrint(allocator, "{s}{d}", .{ ExPackRepoPrefix, self.id });
        }
    }

    pub fn repoFromId(id: u8) RepositoryId {
        return .{ .id = id };
    }

    pub fn repoNameToId(repo_name: []const u8, fallback: bool) !RepositoryId {
        if (std.mem.eql(u8, repo_name, BaseRepoName)) {
            // Explicitly base repo
            return .{ .id = BaseRepoId };
        } else if (std.mem.startsWith(u8, repo_name, ExPackRepoPrefix)) {
            // Expansion pack
            const expack_id = try std.fmt.parseInt(u8, repo_name[2..], 10);
            return .{ .id = expack_id };
        } else {
            if (!fallback) {
                // If not explicitly base repo and not expansion pack, and no base fallback, return error
                return error.InvalidRepo;
            }

            // If not explicitly base repo and not expansion pack, but fallback is allowed, return base repo ID
            return .{ .id = BaseRepoId };
        }
    }
};

test "toString" {
    const allocator = std.testing.allocator;

    {
        const expected = "ffxiv";
        const result = try RepositoryId.base.toString(allocator);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }

    {
        const expected = "ffxiv";
        const result = try RepositoryId.repoFromId(0).toString(allocator);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }

    {
        const expected = "ex1";
        const result = try RepositoryId.repoFromId(1).toString(allocator);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(expected, result);
    }
}

test "repoFromId" {
    const expected = RepositoryId.base;
    const result = RepositoryId.repoFromId(0);
    try std.testing.expectEqual(expected, result);
}

test "repoNameToId" {
    {
        // Resolve base repo name
        const expected = RepositoryId.base;
        const result = try RepositoryId.repoNameToId(RepositoryId.BaseRepoName, false);
        try std.testing.expectEqual(expected, result);
    }

    {
        // Resolve expansion pack repo name
        const expected = RepositoryId.repoFromId(1);
        const result = try RepositoryId.repoNameToId("ex1", false);
        try std.testing.expectEqual(expected, result);
    }

    {
        // Another expansion pack repo name
        const expected = RepositoryId.repoFromId(9);
        const result = try RepositoryId.repoNameToId("ex9", false);
        try std.testing.expectEqual(expected, result);
    }

    {
        // Invalid repo name, no fallback so error
        const expected = error.InvalidRepo;
        const result = RepositoryId.repoNameToId("beep", false);
        try std.testing.expectError(expected, result);
    }

    {
        // Invalid repo name, but fallback is allowed so base repo ID is returned
        const expected = RepositoryId.repoFromId(0);
        const result = try RepositoryId.repoNameToId("beep", true);
        try std.testing.expectEqual(expected, result);
    }
}
