const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const game = try calyx.GameData.init(allocator, .{});
    defer game.deinit();

    const sheet = try game.excel.getSheet("Item");
    const wind_up_raha = try sheet.getRow(23992);
    const wind_up_raha_name = try wind_up_raha.getRowColumnValue(9);
    try std.io.getStdOut().writer().print("Item Name: {s}", .{wind_up_raha_name.string});
}
