const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const game_data = try calyx.GameData.init(allocator, "C:\\Program Files\\SquareEnix\\FINAL FANTASY XIV - A Realm Reborn\\game", .win32);
    defer game_data.deinit();

    const file_content = try game_data.getRawGameFile(allocator, "bgcommon/hou/outdoor/general/0319/bgparts/gar_b0_m0319.mdl");
    defer allocator.free(file_content);

    const root_list = try game_data.getTypedGameFile(allocator, calyx.excel.ExcelList, "exd/root.exl");
    root_list.deinit();
}
