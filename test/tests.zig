const std = @import("std");

test {
    std.testing.log_level = .info;

    std.testing.refAllDeclsRecursive(@import("tests/sqpack.zig"));
    std.testing.refAllDeclsRecursive(@import("tests/excel.zig"));
}
