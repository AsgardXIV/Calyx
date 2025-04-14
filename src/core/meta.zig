const std = @import("std");

pub fn maxEnumValue(comptime E: type) usize {
    var max: usize = 0;
    for (std.meta.fields(E)) |field| {
        if (field.value > max) max = field.value;
    }
    return max;
}

test "maxEnumValue" {
    const MyEnum = enum(u32) {
        A = 1,
        B = 2,
        C = 3,
    };
    try std.testing.expectEqual(3, comptime maxEnumValue(MyEnum));
}
