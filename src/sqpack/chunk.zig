const std = @import("std");
const Allocator = std.mem.Allocator;

const Repository = @import("repository.zig").Repository;
const CategoryID = @import("category_id.zig").CategoryID;
const index = @import("index.zig");
const PathUtils = @import("path_utils.zig").PathUtils;
const FileType = @import("file_type.zig").FileType;

pub const Chunk = struct {
    const Self = @This();

    allocator: Allocator,
    repository: *Repository,
    category_id: CategoryID,
    chunk_id: u8,
    index1: ?*index.Index(index.SqPackIndex1TableEntry),
    index2: ?*index.Index(index.SqPackIndex2TableEntry),

    pub fn init(allocator: Allocator, repository: *Repository, category_id: CategoryID, chunk_id: u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.repository = repository;
        self.category_id = category_id;
        self.chunk_id = chunk_id;
        self.index1 = null;
        self.index2 = null;

        try self.setupIndexes();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.cleanupIndexes();
        self.allocator.destroy(self);
    }

    fn setupIndexes(self: *Self) !void {
        self.index1 = try self.setupIndex(index.SqPackIndex1TableEntry);
        self.index2 = try self.setupIndex(index.SqPackIndex2TableEntry);
    }

    fn setupIndex(self: *Self, comptime T: type) !*index.Index(T) {
        const index_filename = try PathUtils.buildSqPackFileNameTyped(self.allocator, .{
            .category_id = self.category_id,
            .chunk_id = self.chunk_id,
            .file_type = T.IndexFileType,
            .platform = self.repository.pack.game_data.platform,
            .repo_id = self.repository.repo_id,
            .file_idx = null,
        });
        defer self.allocator.free(index_filename);

        const index_path = try std.fs.path.join(self.allocator, &.{ self.repository.repo_path, index_filename });
        defer self.allocator.free(index_path);

        const index_file = std.fs.openFileAbsolute(index_path, .{ .mode = .read_only }) catch null;
        defer if (index_file) |file| file.close();
        if (index_file) |file| {
            return try index.Index(T).init(self.allocator, &file);
        }

        return error.FailedToOpenIndexFile;
    }

    fn cleanupIndexes(self: *Self) void {
        if (self.index1) |idx| idx.deinit();
        if (self.index2) |idx| idx.deinit();
    }
};
