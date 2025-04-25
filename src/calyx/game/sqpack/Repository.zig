const std = @import("std");
const Allocator = std.mem.Allocator;

const Platform = @import("../common/platform.zig").Platform;
const GameVersion = @import("../common/GameVersion.zig");
const RepositoryId = @import("repository_id.zig").RepositoryId;
const Category = @import("Category.zig");
const CategoryId = @import("category_id.zig").CategoryId;
const PackFileName = @import("PackFileName.zig");
const ParsedGamePath = @import("ParsedGamePath.zig");

const core = @import("../../core.zig");

const max_category_id = core.meta.maxEnumValue(CategoryId);

const Repository = @This();

allocator: Allocator,
platform: Platform,
repo_version: GameVersion,
repo_id: RepositoryId,
repo_path: []const u8,
categories: [max_category_id + 1]?*Category,

pub fn init(
    allocator: Allocator,
    platform: Platform,
    default_version: GameVersion,
    repo_id: RepositoryId,
    repo_path: []const u8,
) !*Repository {
    const repo = try allocator.create(Repository);
    errdefer allocator.destroy(repo);

    // We need to clone the sqpack path
    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    repo.* = .{
        .allocator = allocator,
        .platform = platform,
        .repo_version = default_version,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .categories = @splat(null),
    };

    // Setup the version
    try repo.setupVersion();

    // Setup the categories
    try repo.setupCategories();

    return repo;
}

pub fn deinit(repo: *Repository) void {
    repo.cleanupCategories();
    repo.allocator.free(repo.repo_path);
    repo.allocator.destroy(repo);
}

pub fn getFileContents(repo: *Repository, allocator: Allocator, path: ParsedGamePath) ![]const u8 {
    const category = try repo.getCategoryById(path.category_id);
    return category.getFileContents(allocator, path);
}

fn getCategoryById(repo: *Repository, id: CategoryId) !*Category {
    if (repo.categories[@intFromEnum(id)]) |cat| {
        return cat;
    } else {
        return error.InvalidCategory;
    }
}

fn setupCategories(repo: *Repository) !void {
    var sfb = std.heap.stackFallback(2048, repo.allocator);
    const sfa = sfb.get();

    errdefer cleanupCategories(repo); // If we error at all, we need to cleanup

    cat_loop: for (0..max_category_id + 1) |i| {
        // Some values are not valid category ids so we need to skip them
        // Because it's only a few values using a fixed size array is still better than a hash lookup
        const cat_id = std.meta.intToEnum(CategoryId, i) catch continue;

        // There must be at least one index file
        ext_loop: for ([_]PackFileName.Extension{ .index, .index2 }) |ext| {
            const file_name = PackFileName.buildSqPackFileName(
                sfa,
                cat_id,
                repo.repo_id,
                0,
                repo.platform,
                ext,
                null,
            ) catch continue :ext_loop;
            defer sfa.free(file_name);

            const file_path = std.fs.path.join(sfa, &.{ repo.repo_path, file_name }) catch continue :ext_loop;
            defer sfa.free(file_path);

            std.fs.accessAbsolute(file_path, .{}) catch continue :ext_loop;

            break :ext_loop;
        } else {
            continue :cat_loop; // Category has no index
        }

        // Create the category
        const category = try Category.init(
            repo.allocator,
            repo.platform,
            repo.repo_id,
            repo.repo_path,
            cat_id,
        );

        // Store the category
        repo.categories[i] = category;
    }
}

fn cleanupCategories(repo: *Repository) void {
    for (repo.categories, 0..) |cat, i| {
        if (cat) |category| {
            category.deinit();
            repo.categories[i] = null;
        }
    }
}

fn setupVersion(repo: *Repository) !void {
    var sfb = std.heap.stackFallback(2048, repo.allocator);
    const sfa = sfb.get();

    const repo_name = try repo.repo_id.toRepositoryString(sfa);
    defer sfa.free(repo_name);

    const version_file_name = try std.fmt.allocPrint(sfa, "{s}.{s}", .{ repo_name, GameVersion.version_file_extension });
    defer sfa.free(version_file_name);

    const version_file_path = try std.fs.path.join(sfa, &.{ repo.repo_path, version_file_name });
    defer sfa.free(version_file_path);

    const new_version = GameVersion.parseFromFilePath(version_file_path) catch null;
    if (new_version) |ver| {
        repo.repo_version = ver;
    }
}
