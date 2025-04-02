const std = @import("std");
const Allocator = std.mem.Allocator;

const index = @import("index.zig");

const Category = @import("category.zig").Category;
const CategoryId = @import("category_id.zig").CategoryId;

const FileExtension = @import("file_extension.zig").FileExtension;

const path_utils = @import("path_utils.zig");
const PathUtils = path_utils.PathUtils;
const ParsedGamePath = path_utils.ParsedGamePath;
const FileLookupResult = path_utils.FileLookupResult;

const DatFile = @import("virtual_file.zig").DatFile;

pub const Chunk = struct {
    const Self = @This();

    allocator: Allocator,
    category: *Category,
    chunk_id: u8,
    index1: ?*index.Index(index.SqPackIndex1TableEntry),
    index2: ?*index.Index(index.SqPackIndex2TableEntry),
    dat_files: std.AutoArrayHashMapUnmanaged(u8, *DatFile),

    pub fn init(allocator: Allocator, category: *Category, chunk_id: u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .category = category,
            .chunk_id = chunk_id,
            .index1 = null,
            .index2 = null,
            .dat_files = .{},
        };

        try self.setupIndexes();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.cleanupDatFiles();
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

    pub fn loadFile(self: *Self, allocator: Allocator, dat_id: u8, offset: u64) ![]const u8 {
        const dat_file = try self.getDatFile(dat_id);
        return try dat_file.readFile(allocator, offset);
    }

    fn getDatFile(self: *Self, file_id: u8) !*DatFile {
        if (self.dat_files.get(file_id)) |dat_file| {
            return dat_file;
        }

        const dat_file = try DatFile.init(self.allocator, self, file_id);
        errdefer dat_file.deinit();

        try self.dat_files.put(self.allocator, file_id, dat_file);

        return dat_file;
    }

    fn cleanupDatFiles(self: *Self) void {
        for (self.dat_files.values()) |dat_file| {
            dat_file.deinit();
        }
        self.dat_files.deinit(self.allocator);
        self.dat_files = .{};
    }

    fn setupIndexes(self: *Self) !void {
        self.index1 = try self.setupIndex(index.SqPackIndex1TableEntry);
        self.index2 = try self.setupIndex(index.SqPackIndex2TableEntry);
    }

    fn setupIndex(self: *Self, comptime T: type) !*index.Index(T) {
        const index_filename = try PathUtils.buildSqPackFileNameTyped(self.allocator, .{
            .chunk_id = self.chunk_id,
            .file_type = T.IndexFileExtension,
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
