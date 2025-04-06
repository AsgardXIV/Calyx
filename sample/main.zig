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

    try calyx_instance.pack.mountPack();

    const file_content = try calyx_instance.pack.getFileContentsByRawPath(
        allocator,
        "exd/root.exl",
    );
    defer allocator.free(file_content);

    const file_content2 = try calyx_instance.pack.getFileContentsByRawPath(
        allocator,
        "chara/equipment/e0847/texture/v02_c0101e0847_top_mask.tex",
    );
    defer allocator.free(file_content2);

    const file_content3 = try calyx_instance.pack.getFileContentsByRawPath(
        allocator,
        "bgcommon/hou/outdoor/general/0319/bgparts/gar_b0_m0319.mdl",
    );
    defer allocator.free(file_content3);

    const file1 = try std.fs.openFileAbsolute("D:\\exl.exl", .{ .mode = .write_only });
    try file1.writeAll(file_content);
    defer file1.close();

    const file2 = try std.fs.openFileAbsolute("D:\\tex.tex", .{ .mode = .write_only });
    try file2.writeAll(file_content2);
    defer file2.close();

    const file3 = try std.fs.openFileAbsolute("D:\\mdl.mdl", .{ .mode = .write_only });
    try file3.writeAll(file_content3);
    defer file3.close();
}
