const std = @import("std");
const sqpack = @import("sqpack/root.zig");
const common = @import("common/root.zig");
const path_utils = @import("sqpack/path_utils.zig");

const PathUtils = path_utils.PathUtils;

const Allocator = std.mem.Allocator;

/// The `GameData` struct represents the game data instance.
/// It is the main entry point for accessing game files and data.
pub const GameData = struct {
    const Self = @This();

    const GameDataVersionFile = "ffxivgame.ver";
    const SqPackRepoPath = "sqpack";

    allocator: Allocator,
    install_path: []const u8,
    platform: common.Platform,
    pack: *sqpack.SqPack,
    version: common.GameVersion,

    /// Initialize the game data instance.
    ///
    /// The caller must provide an allocator to manage memory for the instance.
    ///
    /// The `install_path` should point to the root directory of the game installation.
    /// It should contain the `ffxivgame.ver` file and the `sqpack` directory.
    ///
    /// The `platform` should be the platform the game files are from.
    ///
    /// Returns a pointer to the initialized `GameData` instance.
    /// The caller is responsible for freeing the instance using `deinit`.
    pub fn init(allocator: Allocator, install_path: []const u8, platform: common.Platform) !*Self {
        var sfb = std.heap.stackFallback(2048, allocator);
        const sfa = sfb.get();

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, install_path);
        errdefer allocator.free(cloned_path);

        const game_version_file_path = try std.fs.path.join(sfa, &.{ install_path, GameDataVersionFile });
        defer sfa.free(game_version_file_path);
        const game_version = common.GameVersion.parseFromFilePath(game_version_file_path) catch common.GameVersion.UnknownVersion;

        const sqpack_repo_path = try std.fs.path.join(sfa, &.{ install_path, SqPackRepoPath });
        defer sfa.free(sqpack_repo_path);

        const pack = try sqpack.SqPack.init(allocator, self, sqpack_repo_path);
        errdefer pack.deinit();

        self.* = Self{
            .allocator = allocator,
            .install_path = cloned_path,
            .platform = platform,
            .pack = pack,
            .version = game_version,
        };

        try self.pack.scanForRepos();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.install_path);
        self.pack.deinit();
        self.allocator.destroy(self);
    }

    /// Get the raw game file bytes from the pack.
    ///
    /// The path should be a valid game file path container within the pack.
    ///
    /// The caller owns the returned buffer and must free it using `allocator.free`.
    pub fn getRawGameFile(self: *Self, allocator: Allocator, path: []const u8) ![]const u8 {
        // Parse the game path to get the repo, category etc.
        const parsed_path = try PathUtils.parseGamePath(path);

        // See if the file exists in the pack indexes
        const lookup_result = self.pack.lookupFile(parsed_path) orelse return error.GameFileNotFound;

        // Get the file content from the pack
        const file_content = try self.pack.loadFile(allocator, lookup_result.repo_id, lookup_result.category_id, lookup_result.chunk_id, lookup_result.data_file_id, lookup_result.data_file_offset);

        return file_content;
    }

    /// Loads a file from the pack and deserializes it into the given type.
    ///
    /// The type `T` must implement the following methods:
    /// - `pub fn init(allocator: Allocator, stream: *std.io.FixedBufferStream([]const u8)) !*Self`
    /// - `pub fn deinit(self: *T) void`
    ///
    /// init must allocate the instance using the provided allocator and initialize it from the stream.
    /// deinit must free the instance using the allocator provided in init.
    ///
    /// The caller owns the returned instance must free it using `T.deinit`.
    pub fn getTypedGameFile(self: *Self, allocator: Allocator, comptime T: type, path: []const u8) !*T {
        // Get the raw game file, use our internal allocator to hold it temporarily
        const file_content = try self.getRawGameFile(self.allocator, path);
        defer self.allocator.free(file_content);

        // Deserialize the file content into the instance
        var stream = std.io.fixedBufferStream(file_content);
        const file_instance = try T.init(allocator, &stream);
        errdefer file_instance.deinit();

        return file_instance;
    }
};
