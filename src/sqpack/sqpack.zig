const std = @import("std");

const Allocator = std.mem.Allocator;

const GameData = @import("../game_data.zig").GameData;
const Repository = @import("repository.zig").Repository;
const PathUtils = @import("path_utils.zig").PathUtils;

pub const SqPack = struct {
    allocator: Allocator,
    game_data: *GameData,
    repos_path: []const u8,
    repos: std.AutoArrayHashMapUnmanaged(u8, *Repository),

    pub fn init(allocator: Allocator, game_data: *GameData, repos_path: []const u8) !*SqPack {
        const self = try allocator.create(SqPack);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, repos_path);
        errdefer allocator.free(cloned_path);

        self.* = .{
            .allocator = allocator,
            .game_data = game_data,
            .repos_path = cloned_path,
            .repos = .{},
        };

        return self;
    }

    pub fn deinit(self: *SqPack) void {
        self.cleanupRepos();
        self.allocator.free(self.repos_path);
        self.allocator.destroy(self);
    }

    pub fn scanForRepos(self: *SqPack) !void {
        self.cleanupRepos();

        var folder = std.fs.openDirAbsolute(self.repos_path, .{ .iterate = true, .no_follow = true }) catch {
            return error.InvalidGameFolder;
        };
        defer folder.close();

        errdefer self.cleanupRepos(); // Cleanup on error

        var walker = try folder.walk(self.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != std.fs.Dir.Entry.Kind.directory) continue;

            const repo_name = entry.basename;
            const repo_id = try PathUtils.repoNameToId(repo_name, false);

            const repo_path = try std.fs.path.join(self.allocator, &.{ self.repos_path, repo_name });
            defer self.allocator.free(repo_path);

            const repo = try Repository.init(self.allocator, self, repo_path, repo_id);

            try self.repos.put(self.allocator, repo_id, repo);
        }
    }

    fn cleanupRepos(self: *SqPack) void {
        for (self.repos.values()) |repo| {
            repo.deinit();
        }
        self.repos.deinit(self.allocator);
        self.repos = .{};
    }
};
