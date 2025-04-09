const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryId = @import("category_id.zig").CategoryId;

const RepositoryId = @import("repository_id.zig").RepositoryId;
const Platform = @import("../platform.zig").Platform;
const ParsedGamePath = @import("ParsedGamePath.zig");

const Chunk = @import("Chunk.zig");

const Category = @This();

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunks: std.AutoHashMapUnmanaged(u8, *Chunk),

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

pub fn getFileContents(category: *Category, allocator: Allocator, path: ParsedGamePath) ![]const u8 {
    var it = category.chunks.valueIterator();
    while (it.next()) |c| {
        const chunk = c.*;
        const lookup = chunk.lookupFileInIndexes(path);
        if (lookup) |resolved| {
            return chunk.getFileContentsAtOffset(allocator, resolved.data_file_id, resolved.data_file_offset);
        }
    }

    return error.FileNotFound;
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
    var it = category.chunks.valueIterator();
    while (it.next()) |chunk| {
        chunk.*.deinit();
    }
    category.chunks.deinit(category.allocator);
}
