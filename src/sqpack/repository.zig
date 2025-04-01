const std = @import("std");
const Allocator = std.mem.Allocator;
const SqPack = @import("sqpack.zig").SqPack;

pub const Repository = struct {
    const Self = @This();

    allocator: Allocator,
    pack: *SqPack,
    repo_path: []const u8,
    repo_id: u8,

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
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.repo_path);
        self.allocator.destroy(self);
    }
};
