const std = @import("std");

pub fn maxEnumValue(comptime E: type) usize {
    var max: usize = 0;
    for (std.meta.fields(E)) |field| {
        if (field.value > max) max = field.value;
    }
    return max;
}

pub const TypeId = *const struct {
    _: u8,
};

pub inline fn typeId(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = T;
        }
        var id: @typeInfo(TypeId).pointer.child = undefined;
    }.id;
}

test "maxEnumValue" {
    const MyEnum = enum(u32) {
        A = 1,
        B = 2,
        C = 3,
    };
    try std.testing.expectEqual(3, comptime maxEnumValue(MyEnum));
}

test "typeId" {
    try std.testing.expectEqual(typeId(u8), typeId(u8));
    try std.testing.expect(typeId(u8) != typeId(u16));
    try std.testing.expectEqual(typeId([]const u8), typeId([]const u8));
    try std.testing.expect(typeId([]const i8) != typeId([]const u8));
}
