const std = @import("std");
const calyx = @import("calyx");

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
    try calyx_instance.excel_system.discoverDefaultDefinitions();

    {
        const sheet = try calyx_instance.excel_system.getSheet("Item");
        const row = try sheet.getRow(15625);
        for (row.columns) |col| {
            switch (col) {
                .string => |s| {
                    std.log.err("String: {s}", .{s});
                },
                else => {},
            }
        }
    }

    {
        const sheet = try calyx_instance.excel_system.getSheet("Item");
        const row = try sheet.getRow(501);
        for (row.columns) |col| {
            switch (col) {
                .string => |s| {
                    std.log.err("String: {s}", .{s});
                },
                else => {},
            }
        }
    }
}
