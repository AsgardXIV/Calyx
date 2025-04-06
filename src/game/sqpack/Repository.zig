const std = @import("std");
const Allocator = std.mem.Allocator;

const GameVersion = @import("../GameVersion.zig");

const RepositoryId = @import("repository_id.zig").RepositoryId;

const Pack = @import("Pack.zig");

const Repository = @This();

allocator: Allocator,
pack: *Pack,
repo_id: RepositoryId,
repo_path: []const u8,
repo_version: GameVersion,

pub fn init(allocator: Allocator, pack: *Pack, repo_id: RepositoryId, repo_path: []const u8) !*Repository {
    const repo = try allocator.create(Repository);
    errdefer allocator.destroy(repo);

    // We need to clone the sqpack path
    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    repo.* = .{
        .allocator = allocator,
        .pack = pack,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .repo_version = GameVersion.UnknownVersion,
    };

    // Setup the version
    try repo.setupVersion();

    return repo;
}

pub fn deinit(repo: *Repository) void {
    repo.allocator.free(repo.repo_path);
    repo.allocator.destroy(repo);
}

fn setupVersion(repo: *Repository) !void {
    var sfb = std.heap.stackFallback(2048, repo.allocator);
    const sfa = sfb.get();

    const repo_name = try repo.repo_id.toRepositoryString(sfa);
    defer sfa.free(repo_name);

    const version_file_name = try std.fmt.allocPrint(sfa, "{s}.{s}", .{ repo_name, GameVersion.GameVersionFileExtension });
    defer sfa.free(version_file_name);

    const version_file_path = try std.fs.path.join(sfa, &.{ repo.repo_path, version_file_name });
    defer sfa.free(version_file_path);

    repo.repo_version = GameVersion.parseFromFilePath(version_file_path) catch repo.pack.calyx.version;
}
