const std = @import("std");

test {
    std.testing.refAllDeclsRecursive(@import("sqpack_test.zig"));
    std.testing.refAllDeclsRecursive(@import("excel_test.zig"));
}
