const std = @import("std");
const Allocator = std.mem.Allocator;
const SqPack = @import("sqpack.zig").SqPack;
const Chunk = @import("chunk.zig").Chunk;

const FileType = @import("file_type.zig").FileType;
const CategoryId = @import("category_id.zig").CategoryId;
const Category = @import("category.zig").Category;

const path_utils = @import("path_utils.zig");
const PathUtils = path_utils.PathUtils;
const ParsedGamePath = path_utils.ParsedGamePath;
const FileLookupResult = path_utils.FileLookupResult;

const RepositoryId = @import("repository_id.zig").RepositoryId;

const GameVersion = @import("../common/game_version.zig").GameVersion;

pub const Repository = struct {
    const Self = @This();

    allocator: Allocator,
    pack: *SqPack,
    repo_path: []const u8,
    repo_id: RepositoryId,
    repo_version: GameVersion,
    categories: std.AutoArrayHashMapUnmanaged(CategoryId, *Category),

    pub fn init(allocator: std.mem.Allocator, pack: *SqPack, repo_path: []const u8, repo_id: RepositoryId) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, repo_path);
        errdefer allocator.free(cloned_path);

        self.* = Self{
            .allocator = allocator,
            .pack = pack,
            .repo_path = cloned_path,
            .repo_id = repo_id,
            .repo_version = undefined,
            .categories = .{},
        };

        try self.setupVersion();
        try self.discoverChunks();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.repo_path);
        self.cleanupCategories();
        self.allocator.destroy(self);
    }

    pub fn lookupFile(self: *Self, path: ParsedGamePath) ?FileLookupResult {
        if (self.categories.get(path.category_id)) |category| {
            return category.lookupFile(path);
        }

        return null;
    }

    pub fn loadFile(self: *Self, allocator: Allocator, category_id: CategoryId, chunk_id: u8, dat_id: u8, offset: u64) ![]const u8 {
        if (self.categories.get(category_id)) |category| {
            return category.loadFile(allocator, chunk_id, dat_id, offset);
        }

        return error.CategoryNotFound;
    }

    fn setupVersion(self: *Self) !void {
        const repo_name = try self.repo_id.toString(self.allocator);
        defer self.allocator.free(repo_name);

        const version_file_name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ repo_name, FileType.ver.toString() });
        defer self.allocator.free(version_file_name);

        const version_file_path = try std.fs.path.join(self.allocator, &.{ self.repo_path, version_file_name });
        defer self.allocator.free(version_file_path);

        self.repo_version = GameVersion.parseFromFilePath(version_file_path) catch self.pack.game_data.version;
    }

    fn discoverChunks(self: *Self) !void {
        var folder = try std.fs.openDirAbsolute(self.repo_path, .{ .iterate = true, .no_follow = true });
        defer folder.close();

        var discovered_unique: std.AutoHashMapUnmanaged(struct { category_id: CategoryId, chunk_id: u8 }, void) = .{};
        defer discovered_unique.deinit(self.allocator);

        errdefer self.cleanupCategories(); // Cleanup on error

        var walker = try folder.walk(self.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            // Only want files
            if (entry.kind != std.fs.Dir.Entry.Kind.file) continue;

            // There must be at least one version file
            const extension = std.fs.path.extension(entry.basename)[1..];
            if (!std.mem.eql(u8, extension, FileType.index.toString()) and
                !std.mem.eql(u8, extension, FileType.index2.toString()))
            {
                continue;
            }

            // Extract what we need
            const sqpack_file = try PathUtils.parseSqPackFileName(entry.basename);

            // Ignore files that don't match the current game data platform
            if (sqpack_file.platform != self.pack.game_data.platform) {
                continue;
            }

            if (!self.categories.contains(sqpack_file.category_id)) {
                const new_category = try Category.init(self.allocator, sqpack_file.category_id, self);
                errdefer new_category.deinit();
                try self.categories.put(self.allocator, sqpack_file.category_id, new_category);
            }

            try self.categories.get(sqpack_file.category_id).?.initChunk(sqpack_file.chunk_id);
        }
    }

    fn cleanupCategories(self: *Self) void {
        for (self.categories.values()) |category| {
            category.deinit();
        }

        self.categories.deinit(self.allocator);
        self.categories = .{};
    }
};
