const std = @import("std");
const Allocator = std.mem.Allocator;

const Category = @import("Category.zig");

const Platform = @import("../platform.zig").Platform;
const RepositoryId = @import("repository_id.zig").RepositoryId;
const CategoryId = @import("category_id.zig").CategoryId;

const Chunk = @This();

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunk_id: u8,

pub fn init(allocator: Allocator, platform: Platform, repo_id: RepositoryId, repo_path: []const u8, category_id: CategoryId, chunk_id: u8) !*Chunk {
    const chunk = try allocator.create(Chunk);
    errdefer allocator.destroy(chunk);

    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    chunk.* = .{
        .allocator = allocator,
        .platform = platform,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .category_id = category_id,
        .chunk_id = chunk_id,
    };

    return chunk;
}

pub fn deinit(chunk: *Chunk) void {
    chunk.allocator.free(chunk.repo_path);
    chunk.allocator.destroy(chunk);
}
