const std = @import("std");
const calyx = @import("calyx");

const ExcelList = calyx.game.excel.ExcelList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const calyx_instance = try calyx.Calyx.init(
        allocator,
        "C:\\Program Files\\SquareEnix\\FINAL FANTASY XIV - A Realm Reborn\\game",
        .win32,
        .english,
    );
    defer calyx.Calyx.deinit(calyx_instance);

    // Init sqpack
    try calyx_instance.pack.mountPack();

    // Read standard file
    const file_content = try calyx_instance.pack.getFileContents(
        allocator,
        "exd/root.exl",
    );
    defer allocator.free(file_content);

    // Read texture file
    const file_content2 = try calyx_instance.pack.getFileContents(
        allocator,
        "chara/equipment/e0847/texture/v02_c0101e0847_top_mask.tex",
    );
    defer allocator.free(file_content2);

    // Read model file
    const file_content3 = try calyx_instance.pack.getFileContents(
        allocator,
        "chara/equipment/e0847/model/c0101e0847_top.mdl",
    );
    defer allocator.free(file_content3);

    // Init excel system
    try calyx_instance.excel_system.precacheSheetDefinitions();

    const sheet = try calyx_instance.excel_system.getSheetByName("ActionTimeline", null, true);
    std.debug.print("Sheet: {d}\n", .{sheet.rows.size});
    const row = sheet.getRow(3);
    if (row) |r| {
        for (r.columns) |col| {
            switch (col) {
                .u16 => |v| {
                    std.debug.print("u16: {}\n", .{v});
                },
                .string => |v| {
                    std.debug.print("string: {s}\n", .{v});
                },
                else => {},
            }
        }
    }

    const sheet_2 = try calyx_instance.excel_system.getSheetByName("Item", calyx.game.Language.english, false);
    _ = sheet_2;
}
