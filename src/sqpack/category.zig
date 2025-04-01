const std = @import("std");

const Allocator = std.mem.Allocator;

const Repository = @import("repository.zig").Repository;
const CategoryID = @import("category_id.zig").CategoryID;
const Chunk = @import("chunk.zig").Chunk;
const ParsedGamePath = @import("path_utils.zig").ParsedGamePath;
const FileLookupResult = @import("path_utils.zig").FileLookupResult;

pub const Category = struct {
    const Self = @This();

    allocator: Allocator,
    category_id: CategoryID,
    repository: *Repository,
    chunks: std.AutoArrayHashMapUnmanaged(u8, *Chunk),

    pub fn init(allocator: Allocator, category_id: CategoryID, repository: *Repository) !*Category {
        const self = try allocator.create(Category);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .category_id = category_id,
            .repository = repository,
            .chunks = .{},
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.cleanupChunks();
        self.allocator.destroy(self);
    }

    pub fn initChunk(self: *Self, chunk_id: u8) !void {
        if (!self.chunks.contains(chunk_id)) {
            const new_chunk = try Chunk.init(self.allocator, self, chunk_id);
            try self.chunks.put(self.allocator, chunk_id, new_chunk);
        }
    }

    pub fn lookupFile(self: *Self, path: ParsedGamePath) ?FileLookupResult {
        for (self.chunks.values()) |chunk| {
            if (chunk.lookupFile(path)) |result| {
                return result;
            }
        }

        return null;
    }

    fn cleanupChunks(self: *Self) void {
        for (self.chunks.values()) |chunk| {
            chunk.deinit();
        }
        self.chunks.deinit(self.allocator);
        self.chunks = .{};
    }
};
