const std = @import("std");

const Allocator = std.mem.Allocator;

const Repository = @import("repository.zig").Repository;
const CategoryId = @import("category_id.zig").CategoryId;
const Chunk = @import("chunk.zig").Chunk;

const path_utils = @import("path_utils.zig");
const ParsedGamePath = path_utils.ParsedGamePath;
const FileLookupResult = path_utils.FileLookupResult;

pub const Category = struct {
    const Self = @This();

    allocator: Allocator,
    category_id: CategoryId,
    repository: *Repository,
    chunks: std.AutoArrayHashMapUnmanaged(u8, *Chunk),

    pub fn init(allocator: Allocator, category_id: CategoryId, repository: *Repository) !*Category {
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

    pub fn loadFile(self: *Self, allocator: Allocator, chunk_id: u8, dat_id: u8, offset: u64) ![]const u8 {
        if (self.chunks.get(chunk_id)) |chunk| {
            return chunk.loadFile(allocator, dat_id, offset);
        }

        return error.ChunkNotFound;
    }

    fn cleanupChunks(self: *Self) void {
        for (self.chunks.values()) |chunk| {
            chunk.deinit();
        }
        self.chunks.deinit(self.allocator);
        self.chunks = .{};
    }
};
