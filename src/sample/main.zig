const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Init Calyx
    const game = try calyx.GameData.init(allocator, .{});
    defer game.deinit();

    // Read a game file
    const swine_head_model = try game.getFileContents(allocator, "chara/equipment/e6023/model/c0101e6023_met.mdl");
    defer allocator.free(swine_head_model);
    try std.io.getStdOut().writer().print("Swine Head model length: {d} bytes\n", .{swine_head_model.len});

    // Read from Excel
    const sheet = try game.getSheet("Item");
    const wind_up_raha = try sheet.getRow(23992);
    const wind_up_raha_name = try wind_up_raha.getRowColumnValue(9);
    try std.io.getStdOut().writer().print("Item Name: {s}\n", .{wind_up_raha_name.string});
}
