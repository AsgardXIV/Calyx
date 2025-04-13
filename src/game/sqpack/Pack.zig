const std = @import("std");
const Allocator = std.mem.Allocator;

const Platform = @import("../platform.zig").Platform;
const GameVersion = @import("../GameVersion.zig");
const Repository = @import("Repository.zig");
const RepositoryId = @import("repository_id.zig").RepositoryId;
const ParsedGamePath = @import("ParsedGamePath.zig");

const Pack = @This();

allocator: Allocator,
platform: Platform,
version: GameVersion,
pack_path: []const u8,
repos_loaded: bool,
repos: std.ArrayListUnmanaged(*Repository),

pub fn init(
    allocator: Allocator,
    platform: Platform,
    version: GameVersion,
    pack_path: []const u8,
) !*Pack {
    const pack = try allocator.create(Pack);
    errdefer allocator.destroy(pack);

    // We need to clone the sqpack path
    const cloned_pack_path = try allocator.dupe(u8, pack_path);
    errdefer allocator.free(cloned_pack_path);

    // Populate instance
    pack.* = .{
        .allocator = allocator,
        .pack_path = cloned_pack_path,
        .platform = platform,
        .version = version,
        .repos_loaded = false,
        .repos = .{},
    };

    return pack;
}

pub fn deinit(pack: *Pack) void {
    pack.cleanupRepos();
    pack.allocator.free(pack.pack_path);
    pack.allocator.destroy(pack);
}

pub fn getFileContents(pack: *Pack, allocator: Allocator, raw_path: []const u8) ![]const u8 {
    const parsed_path = try ParsedGamePath.fromPathString(raw_path);
    const repo = try getRepoById(pack, parsed_path.repo_id);
    return repo.getFileContents(allocator, parsed_path);
}

pub fn getTypedFile(pack: *Pack, allocator: Allocator, comptime FileType: type, path: []const u8) !*FileType {
    // Get the raw file contents
    const raw_contents = try pack.getFileContents(pack.allocator, path);
    defer allocator.free(raw_contents);

    // Create a buffered stream reader
    var fbs = std.io.fixedBufferStream(raw_contents);

    // Deserialize the file contents
    const typed_contents = try FileType.init(allocator, &fbs);
    errdefer typed_contents.deinit();

    return typed_contents;
}

pub fn loadRepos(pack: *Pack) !void {
    if (pack.repos_loaded) return;

    var sfb = std.heap.stackFallback(2048, pack.allocator);
    const sfa = sfb.get();

    errdefer pack.cleanupRepos(); // If we error at all, we need to cleanup

    var max_seen: i16 = -1;

    // Each folder represents a repository, we just identify them first pass
    var folder = std.fs.openDirAbsolute(pack.pack_path, .{ .iterate = true, .access_sub_paths = false, .no_follow = true }) catch {
        return error.InvalidPackFolder;
    };
    errdefer folder.close();

    var walker = try folder.walk(sfa);
    errdefer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != std.fs.Dir.Entry.Kind.directory) continue;

        const repo_name = entry.basename;
        const repo_id = try RepositoryId.fromRepositoryString(repo_name, false);
        const repo_int = repo_id.toIntId();

        if (repo_int > max_seen) {
            max_seen = repo_int;
        }
    }
    walker.deinit();
    folder.close();

    if (max_seen < 0) {
        return error.InvalidPackFolder;
    }
    max_seen += 1;

    // Load the repos
    const repo_count: u8 = @intCast(max_seen);
    try pack.repos.ensureTotalCapacity(pack.allocator, repo_count + 1);
    for (0..repo_count) |repo_int| {
        const repo_id = RepositoryId.fromIntId(@intCast(repo_int));
        const repo_name = try repo_id.toRepositoryString(pack.allocator);
        defer pack.allocator.free(repo_name);

        const repo_path = try std.fs.path.join(sfa, &.{ pack.pack_path, repo_name });
        defer sfa.free(repo_path);

        const repo = try Repository.init(
            pack.allocator,
            pack.platform,
            pack.version,
            repo_id,
            repo_path,
        );

        pack.repos.appendAssumeCapacity(repo);
    }
}

fn getRepoById(pack: *Pack, repo_id: RepositoryId) !*Repository {
    try pack.loadIfRequired();

    const index = repo_id.toIntId();

    if (index >= pack.repos.items.len) {
        return error.InvalidRepositoryId;
    }

    return pack.repos.items[index];
}

inline fn loadIfRequired(pack: *Pack) !void {
    if (!pack.repos_loaded) {
        try pack.loadRepos();
        pack.repos_loaded = true;
    }
}

fn cleanupRepos(pack: *Pack) void {
    pack.repos_loaded = false;
    for (pack.repos.items) |repo| {
        repo.deinit();
    }
    pack.repos.deinit(pack.allocator);
}
