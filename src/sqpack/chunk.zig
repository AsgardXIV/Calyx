const std = @import("std");
const Allocator = std.mem.Allocator;

const Repository = @import("repository.zig").Repository;
const CategoryID = @import("category_id.zig").CategoryID;

pub const Chunk = struct {
    const Self = @This();

    allocator: Allocator,
    repository: *Repository,
    category_id: CategoryID,
    chunk_id: u8,

    pub fn init(allocator: Allocator, repository: *Repository, category_id: CategoryID, chunk_id: u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .repository = repository,
            .category_id = category_id,
            .chunk_id = chunk_id,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};
