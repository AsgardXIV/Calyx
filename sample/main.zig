const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const game_data = try calyx.GameData.init(allocator, "C:\\Program Files\\SquareEnix\\FINAL FANTASY XIV - A Realm Reborn\\game", .win32);
    defer game_data.deinit();

    std.log.info("Game Version: {s}", .{game_data.version.versionString()});
    std.log.info("Discovered Repos: {d}", .{game_data.pack.repos.count()});
    for (game_data.pack.repos.values()) |repo| {
        std.log.info("- Repo ID: {d}", .{repo.repo_id});
        std.log.info("- Repo Path: {s}", .{repo.repo_path});
        std.log.info("- Discovered Chunks: {d}", .{repo.chunks.capacity});
        for (repo.chunks.items) |chunk| {
            std.log.info("-- Chunk ID: {d}", .{chunk.chunk_id});
            std.log.info("-- Chunk Category ID: {d} {s}", .{ @intFromEnum(chunk.category_id), chunk.category_id.toString() });
        }
    }
}
