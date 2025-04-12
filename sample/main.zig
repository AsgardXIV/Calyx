const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const game = try calyx.GameData.init(allocator, .{});
    try game.pack.loadRepos();
    defer game.deinit();

    const content = try game.getFileContents(allocator, "chara/equipment/e0436/model/c0101e0436_top.mdl");
    std.log.err("File contents: {d}\n", .{content.len});
    defer allocator.free(content);
}
