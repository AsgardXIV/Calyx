const std = @import("std");
const sqpack = @import("sqpack/root.zig");
const common = @import("common/root.zig");
const path_utils = @import("sqpack/path_utils.zig");

const PathUtils = path_utils.PathUtils;

const Allocator = std.mem.Allocator;

pub const GameData = struct {
    const Self = @This();

    const GameDataVersionFile = "ffxivgame.ver";
    const SqPackRepoPath = "sqpack";

    allocator: Allocator,
    install_path: []const u8,
    platform: common.Platform,
    pack: *sqpack.SqPack,
    version: common.GameVersion,

    pub fn init(allocator: Allocator, install_path: []const u8, platform: common.Platform) !*Self {
        var sfb = std.heap.stackFallback(2048, allocator);
        const sfa = sfb.get();

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, install_path);
        errdefer allocator.free(cloned_path);

        const game_version_file_path = try std.fs.path.join(sfa, &.{ install_path, GameDataVersionFile });
        defer sfa.free(game_version_file_path);
        const game_version = common.GameVersion.parseFromFilePath(game_version_file_path) catch common.GameVersion.unknown;

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

    pub fn getGameFileHandle(self: *Self, path: []const u8) !void {
        const parsed_path = try PathUtils.parseGamePath(path);
        const lookup_result = self.pack.lookupFile(parsed_path) orelse return error.GameFileNotFound;
        const file_content = try self.pack.loadFile(self.allocator, lookup_result.repo_id, lookup_result.category_id, lookup_result.chunk_id, lookup_result.data_file_id, lookup_result.data_file_offset);
        defer self.allocator.free(file_content);
    }
};
