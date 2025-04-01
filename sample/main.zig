const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const game_data = try calyx.GameData.init(allocator, "C:\\Program Files\\SquareEnix\\FINAL FANTASY XIV - A Realm Reborn\\game", .win32);
    defer game_data.deinit();

    std.log.info("Game Version: {s}", .{game_data.version.versionString()});
}
