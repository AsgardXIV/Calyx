const std = @import("std");
const Allocator = std.mem.Allocator;
const SqPack = @import("sqpack.zig").SqPack;
const Chunk = @import("chunk.zig").Chunk;
const PathUtils = @import("path_utils.zig").PathUtils;
const FileType = @import("file_type.zig").FileType;
const CategoryID = @import("category_id.zig").CategoryID;

pub const Repository = struct {
    const Self = @This();

    allocator: Allocator,
    pack: *SqPack,
    repo_path: []const u8,
    repo_id: u8,
    chunks: std.ArrayListUnmanaged(*Chunk),

    pub fn init(allocator: std.mem.Allocator, pack: *SqPack, repo_path: []const u8, repo_id: u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, repo_path);
        errdefer allocator.free(cloned_path);

        self.* = Self{
            .allocator = allocator,
            .pack = pack,
            .repo_path = cloned_path,
            .repo_id = repo_id,
            .chunks = .{},
        };

        try self.discoverChunks();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.repo_path);
        self.cleanupChunks();
        self.allocator.destroy(self);
    }

    fn discoverChunks(self: *Self) !void {
        var folder = try std.fs.openDirAbsolute(self.repo_path, .{ .iterate = true, .no_follow = true });
        defer folder.close();

        var discovered_unique: std.AutoHashMapUnmanaged(struct { category_id: CategoryID, chunk_id: u8 }, void) = .{};
        defer discovered_unique.deinit(self.allocator);

        errdefer self.cleanupChunks(); // Cleanup on error

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

            // Add to the discovered unique list
            try discovered_unique.put(self.allocator, .{
                .category_id = sqpack_file.category_id,
                .chunk_id = sqpack_file.chunk_id,
            }, void{});
        }

        // Now we can create the unique chunks
        var unique_it = discovered_unique.keyIterator();
        while (unique_it.next()) |entry| {
            // Create the chunk
            const chunk = try Chunk.init(self.allocator, self, entry.category_id, entry.chunk_id);
            try self.chunks.append(self.allocator, chunk);
        }
    }

    fn cleanupChunks(self: *Self) void {
        for (self.chunks.items) |chunk| {
            chunk.deinit();
        }
        self.chunks.deinit(self.allocator);
        self.chunks = .{};
    }
};
