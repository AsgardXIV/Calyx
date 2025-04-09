const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const calyx_instance = try calyx.Calyx.init(
        allocator,
        null,
        .win32,
        .english,
    );
    defer calyx.Calyx.deinit(calyx_instance);

    // Init sqpack
    try calyx_instance.pack.mountPack();
}
