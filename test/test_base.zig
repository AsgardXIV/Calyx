const std = @import("std");

const calyx_lib = @import("calxy");
const Calyx = calyx_lib.Calyx;

pub fn startCalyx() !*Calyx {
    std.testing.log_level = .info;

    const calyx = try Calyx.init(
        std.testing.allocator,
        null,
        .win32,
        .english,
    );
    try calyx.pack.mountPack();
    return calyx;
}
