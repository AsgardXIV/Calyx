const std = @import("std");
const Allocator = std.mem.Allocator;

const Calyx = @import("../../Calyx.zig");

const Repository = @import("Repository.zig");
const RepositoryId = @import("repository_id.zig").RepositoryId;

const GameVersion = @import("../GameVersion.zig");

const Platform = @import("../platform.zig").Platform;

const Pack = @This();

allocator: Allocator,
platform: Platform,
version: GameVersion,
pack_path: []const u8,
repos: std.AutoArrayHashMapUnmanaged(RepositoryId, *Repository),

/// Initializes a new pack instance.
///
/// The pack is not mounted by default.
///
/// The caller must provide an allocator to manage memory for the instance.
///
/// The `calyx` pointer should point to the `Calyx` instance that this pack is associated with.
///
/// The `pack_path` should point to the root directory of the pack.
/// Typically the `sqpack` directory.
///
/// Returns a pointer to the initialized `Pack` instance.
pub fn init(allocator: Allocator, platform: Platform, version: GameVersion, pack_path: []const u8) !*Pack {
    const pack = try allocator.create(Pack);
    errdefer allocator.destroy(pack);

    // We need to clone the sqpack path
    const cloned_pack_path = try allocator.dupe(u8, pack_path);
    errdefer allocator.free(cloned_pack_path);

    pack.* = .{
        .allocator = allocator,
        .pack_path = cloned_pack_path,
        .platform = platform,
        .version = version,
        .repos = .{},
    };

    return pack;
}

/// Deinitializes the `Pack` instance.
///
/// The caller should not use the `Pack` instance after this function is called.
pub fn deinit(pack: *Pack) void {
    pack.unmountPack();
    pack.allocator.free(pack.pack_path);
    pack.allocator.destroy(pack);
}

/// Mounts the pack.
///
/// This function will discover and load all repositories in the pack.
/// It will automatically unmount any previously mounted repositories.
pub fn mountPack(pack: *Pack) !void {
    std.log.info("Mounting sqpack...", .{});

    var sfb = std.heap.stackFallback(2048, pack.allocator);
    const sfa = sfb.get();

    pack.unmountPack();

    var folder = std.fs.openDirAbsolute(pack.pack_path, .{ .iterate = true, .no_follow = true }) catch {
        return error.InvalidGameFolder;
    };
    defer folder.close();

    errdefer pack.unmountPack(); // Unmount if there is any error

    // Each folder represents a repository
    var walker = try folder.walk(sfa);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != std.fs.Dir.Entry.Kind.directory) continue;

        const repo_name = entry.basename;
        const repo_id = try RepositoryId.fromRepositoryString(repo_name, false);

        const repo_path = try std.fs.path.join(sfa, &.{ pack.pack_path, repo_name });
        defer sfa.free(repo_path);

        const repo = try Repository.init(
            pack.allocator,
            pack.platform,
            pack.version,
            repo_id,
            repo_path,
        );

        try pack.repos.put(pack.allocator, repo_id, repo);
    }

    std.log.info("Mounted sqpack with {d} repositories.", .{pack.repos.count()});
}

/// Unmounts the pack.
///
/// This function will unload all repositories in the pack.
/// It is safe to call this function even if the pack is not mounted.
/// Any existing references to the repositories will be invalidated.
pub fn unmountPack(pack: *Pack) void {
    for (pack.repos.values()) |repo| {
        repo.deinit();
    }
    pack.repos.deinit(pack.allocator);
    pack.repos = .{};
}
