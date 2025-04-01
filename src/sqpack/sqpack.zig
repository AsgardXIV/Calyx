const std = @import("std");

const Allocator = std.mem.Allocator;

const GameData = @import("../game_data.zig").GameData;

pub const SqPack = struct {
    allocator: Allocator,
    game_data: *GameData,
    repos_path: []const u8,

    pub fn init(allocator: Allocator, game_data: *GameData, repos_path: []const u8) !*SqPack {
        const self = try allocator.create(SqPack);
        errdefer allocator.destroy(self);

        const cloned_path = try allocator.dupe(u8, repos_path);
        errdefer allocator.free(cloned_path);

        self.* = .{
            .allocator = allocator,
            .game_data = game_data,
            .repos_path = cloned_path,
        };

        return self;
    }

    pub fn deinit(self: *SqPack) void {
        self.allocator.free(self.repos_path);
        self.allocator.destroy(self);
    }
};
