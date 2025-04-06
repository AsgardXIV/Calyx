const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryId = @import("category_id.zig").CategoryId;

const Repository = @import("Repository.zig");

const Category = @This();

allocator: Allocator,
repo: *Repository,
category_id: CategoryId,

pub fn init(allocator: Allocator, repo: *Repository, category_id: CategoryId) !*Category {
    const category = try allocator.create(Category);
    errdefer allocator.destroy(category);

    category.* = .{
        .allocator = allocator,
        .repo = repo,
        .category_id = category_id,
    };

    return category;
}

pub fn deinit(category: *Category) void {
    category.allocator.destroy(category);
}

pub fn chunkDiscovered(category: *Category, chunk_id: u8) !void {
    _ = chunk_id;
    _ = category;
}
