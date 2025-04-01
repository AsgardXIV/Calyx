const std = @import("std");
const Allocator = std.mem.Allocator;

const Category = @import("category.zig").Category;
const CategoryID = @import("category_id.zig").CategoryID;
const index = @import("index.zig");

const FileType = @import("file_type.zig").FileType;

const path_utils = @import("path_utils.zig");
const PathUtils = path_utils.PathUtils;
const ParsedGamePath = path_utils.ParsedGamePath;
const FileLookupResult = path_utils.FileLookupResult;

pub const Chunk = struct {
    const Self = @This();

    allocator: Allocator,
    category: *Category,
    chunk_id: u8,
    index1: ?*index.Index(index.SqPackIndex1TableEntry),
    index2: ?*index.Index(index.SqPackIndex2TableEntry),

    pub fn init(allocator: Allocator, category: *Category, chunk_id: u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.category = category;
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

    pub fn lookupFile(self: *Self, path: ParsedGamePath) ?FileLookupResult {
        if (self.index1) |idx| {
            if (idx.lookupFile(path)) |result| {
                return result;
            }
        }

        if (self.index2) |idx| {
            if (idx.lookupFile(path)) |result| {
                return result;
            }
        }

        return null;
    }

    fn setupIndexes(self: *Self) !void {
        self.index1 = try self.setupIndex(index.SqPackIndex1TableEntry);
        self.index2 = try self.setupIndex(index.SqPackIndex2TableEntry);
    }

    fn setupIndex(self: *Self, comptime T: type) !*index.Index(T) {
        const index_filename = try PathUtils.buildSqPackFileNameTyped(self.allocator, .{
            .chunk_id = self.chunk_id,
            .file_type = T.IndexFileType,
            .category_id = self.category.category_id,
            .platform = self.category.repository.pack.game_data.platform,
            .repo_id = self.category.repository.repo_id,
            .file_idx = null,
        });
        defer self.allocator.free(index_filename);

        const index_path = try std.fs.path.join(self.allocator, &.{ self.category.repository.repo_path, index_filename });
        defer self.allocator.free(index_path);

        const index_file = std.fs.openFileAbsolute(index_path, .{ .mode = .read_only }) catch null;
        defer if (index_file) |file| file.close();
        if (index_file) |file| {
            return try index.Index(T).init(self.allocator, self, &file);
        }

        return error.FailedToOpenIndexFile;
    }

    fn cleanupIndexes(self: *Self) void {
        if (self.index1) |idx| idx.deinit();
        if (self.index2) |idx| idx.deinit();
    }
};
