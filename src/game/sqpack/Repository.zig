const std = @import("std");
const Allocator = std.mem.Allocator;

const GameVersion = @import("../GameVersion.zig");

const RepositoryId = @import("repository_id.zig").RepositoryId;

const Pack = @import("Pack.zig");

const Repository = @This();

const Category = @import("category.zig");
const CategoryId = @import("category_id.zig").CategoryId;
const PackFileName = @import("PackFileName.zig");

allocator: Allocator,
pack: *Pack,
repo_id: RepositoryId,
repo_path: []const u8,
repo_version: GameVersion,
categories: std.AutoArrayHashMapUnmanaged(CategoryId, *Category),

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
        .categories = .{},
    };

    // Setup the version
    try repo.setupVersion();

    // Discover the categories
    try repo.discoverCategories();

    return repo;
}

pub fn deinit(repo: *Repository) void {
    repo.cleanupCategories();
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

fn discoverCategories(repo: *Repository) !void {
    var sfb = std.heap.stackFallback(2048, repo.allocator);
    const sfa = sfb.get();

    errdefer cleanupCategories(repo);

    var folder = try std.fs.openDirAbsolute(repo.repo_path, .{ .iterate = true, .no_follow = true });
    defer folder.close();

    var walker = try folder.walk(sfa);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        // Only want files
        if (entry.kind != std.fs.Dir.Entry.Kind.file) continue;

        // There must be at least one index file
        const extension = std.fs.path.extension(entry.basename)[1..];
        if (!std.mem.eql(u8, extension, PackFileName.Extension.index.toExensionString()) and
            !std.mem.eql(u8, extension, PackFileName.Extension.index2.toExensionString()))
        {
            continue;
        }

        // Parse it
        const file_name = try PackFileName.fromPackFileString(entry.basename);

        // Correct platform?
        if (file_name.platform != repo.pack.calyx.platform) continue;

        // If we haven't seen this category before, create it
        if (!repo.categories.contains(file_name.category_id)) {
            const category = try Category.init(repo.allocator, repo, file_name.category_id);
            errdefer category.deinit();

            // Add it to the map
            try repo.categories.put(repo.allocator, file_name.category_id, category);
        }

        // By now we must have a category
        const category = repo.categories.get(file_name.category_id) orelse unreachable;

        // Inform the category of the chunk, it's ok if it already exists
        try category.chunkDiscovered(file_name.chunk_id);
    }
}

fn cleanupCategories(repo: *Repository) void {
    for (repo.categories.values()) |category| {
        category.deinit();
    }
    repo.categories.deinit(repo.allocator);
}
