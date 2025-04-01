const std = @import("std");
const sqpack = @import("sqpack/root.zig");
const common = @import("common/root.zig");

const Allocator = std.mem.Allocator;

pub const GameData = struct {
    const Self = @This();

    allocator: Allocator,
    install_path: []const u8,
    pack: ?*sqpack.SqPack,
    version: common.GameVersion,

    pub fn init(allocator: Allocator, install_path: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, install_path);
        errdefer allocator.free(cloned_path);

        const game_version = try common.GameVersion.parseFromString("2025.03.27.0000.0000");

        self.* = Self{
            .allocator = allocator,
            .install_path = cloned_path,
            .pack = null,
            .version = game_version,
        };

        return self;
    }
};
