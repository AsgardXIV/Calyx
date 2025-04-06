const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryId = @import("category_id.zig").CategoryId;

const RepositoryId = @import("repository_id.zig").RepositoryId;
const Platform = @import("../platform.zig").Platform;

const Chunk = @import("Chunk.zig");

const Category = @This();

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunks: std.AutoArrayHashMapUnmanaged(u8, *Chunk),

pub fn init(allocator: Allocator, platform: Platform, repo_id: RepositoryId, repo_path: []const u8, category_id: CategoryId) !*Category {
    const category = try allocator.create(Category);
    errdefer allocator.destroy(category);

    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    category.* = .{
        .allocator = allocator,
        .platform = platform,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .category_id = category_id,
        .chunks = .{},
    };

    return category;
}

pub fn deinit(category: *Category) void {
    category.cleanupChunks();
    category.allocator.free(category.repo_path);
    category.allocator.destroy(category);
}

pub fn chunkDiscovered(category: *Category, chunk_id: u8) !void {
    if (!category.chunks.contains(chunk_id)) {
        const chunk = try Chunk.init(
            category.allocator,
            category.platform,
            category.repo_id,
            category.repo_path,
            category.category_id,
            chunk_id,
        );
        errdefer chunk.deinit();

        try category.chunks.put(category.allocator, chunk_id, chunk);
    }
}

fn cleanupChunks(category: *Category) void {
    for (category.chunks.values()) |chunk| {
        chunk.deinit();
    }
    category.chunks.deinit(category.allocator);
}
