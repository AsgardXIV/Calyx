const std = @import("std");
const Allocator = std.mem.Allocator;

const Calyx = @import("../../Calyx.zig");

const Pack = @This();

allocator: Allocator,
calyx: *Calyx,
pack_path: []const u8,

pub fn init(allocator: Allocator, calyx: *Calyx, pack_path: []const u8) !*Pack {
    const pack = try allocator.create(Pack);
    errdefer allocator.destroy(pack);

    // We need to clone the sqpack path
    const cloned_pack_path = try allocator.dupe(u8, pack_path);
    errdefer allocator.free(cloned_pack_path);

    pack.* = .{
        .allocator = allocator,
        .calyx = calyx,
        .pack_path = cloned_pack_path,
    };

    return pack;
}

pub fn deinit(pack: *Pack) void {
    pack.allocator.free(pack.pack_path);
    pack.allocator.destroy(pack);
}
