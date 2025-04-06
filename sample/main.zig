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

    const file_content2 = try calyx_instance.pack.getFileContentsByRawPath(
        allocator,
        "bgcommon/hou/outdoor/general/0319/bgparts/gar_b0_m0319.mdl",
    );

    allocator.free(file_content);
    allocator.free(file_content2);
}
