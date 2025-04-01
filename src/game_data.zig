const std = @import("std");
const sqpack = @import("sqpack/root.zig");
const common = @import("common/root.zig");

const Allocator = std.mem.Allocator;

pub const GameData = struct {
    const Self = @This();

    const GameDataVersionFile = "ffxivgame.ver";
    const SqPackRepoPath = "sqpack";

    allocator: Allocator,
    install_path: []const u8,
    pack: *sqpack.SqPack,
    version: common.GameVersion,

    pub fn init(allocator: Allocator, install_path: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, install_path);
        errdefer allocator.free(cloned_path);

        const game_version_file_path = try std.fs.path.join(allocator, &.{ install_path, GameDataVersionFile });
        defer allocator.free(game_version_file_path);
        const game_version = try common.GameVersion.parseFromFilePath(game_version_file_path);

        const sqpack_repo_path = try std.fs.path.join(allocator, &.{ install_path, SqPackRepoPath });
        defer allocator.free(sqpack_repo_path);

        const pack = try sqpack.SqPack.init(allocator, self, sqpack_repo_path);
        errdefer pack.deinit();

        self.* = Self{
            .allocator = allocator,
            .install_path = cloned_path,
            .pack = pack,
            .version = game_version,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.install_path);
        self.pack.deinit();
        self.allocator.destroy(self);
    }
};
