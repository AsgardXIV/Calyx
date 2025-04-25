const std = @import("std");

/// Determines the maximum value of an enum type.
pub fn maxEnumValue(comptime E: type) usize {
    var max: usize = 0;
    for (std.meta.fields(E)) |field| {
        if (field.value > max) max = field.value;
    }
    return max;
}

/// Determine if an enum has a specific flag set.
pub fn enumHasFlag(
    enumeration: anytype,
    flag: @TypeOf(enumeration),
) bool {
    comptime {
        if (@typeInfo(@TypeOf(enumeration)) != .@"enum") {
            @compileError("enumHasFlag requires an enum type");
        }
    }

    return (@intFromEnum(enumeration) & @intFromEnum(flag)) != 0;
}

/// Determine if an enum has all of the specified flags set.
pub fn enumHasAllFlags(enumeration: anytype, flags: []const @TypeOf(enumeration)) bool {
    comptime {
        if (@typeInfo(@TypeOf(enumeration)) != .@"enum") {
            @compileError("enumHasAllFlags requires an enum type");
        }
    }

    for (flags) |f| {
        if (!enumHasFlag(enumeration, f)) {
            return false;
        }
    }
    return true;
}

/// Determine if an enum has any of the specified flags set.
pub fn enumHasAnyFlags(enumeration: anytype, flags: []const @TypeOf(enumeration)) bool {
    comptime {
        if (@typeInfo(@TypeOf(enumeration)) != .@"enum") {
            @compileError("enumHasAllFlags requires an enum type");
        }
    }

    for (flags) |f| {
        if (enumHasFlag(enumeration, f)) {
            return true;
        }
    }
    return false;
}

test maxEnumValue {
    const MyEnum = enum(u32) {
        A = 1,
        B = 2,
        C = 3,
    };
    try std.testing.expectEqual(3, comptime maxEnumValue(MyEnum));
}

test enumHasFlag {
    const MyEnum = enum(u32) {
        A = 0x1,
        B = 0x2,
        C = 0x4,
        _,
    };

    const value: MyEnum = @enumFromInt(@intFromEnum(MyEnum.A) | @intFromEnum(MyEnum.B));
    try std.testing.expectEqual(true, enumHasFlag(value, MyEnum.A));
    try std.testing.expectEqual(false, enumHasFlag(value, MyEnum.C));
}

test enumHasAllFlags {
    const MyEnum = enum(u32) {
        A = 0x1,
        B = 0x2,
        C = 0x4,
        _,
    };

    const value: MyEnum = @enumFromInt(@intFromEnum(MyEnum.A) | @intFromEnum(MyEnum.B));
    try std.testing.expectEqual(true, enumHasAllFlags(value, &.{ MyEnum.A, MyEnum.B }));
    try std.testing.expectEqual(false, enumHasAllFlags(value, &.{ MyEnum.A, MyEnum.B, MyEnum.C }));
}

test enumHasAnyFlags {
    const MyEnum = enum(u32) {
        A = 0x1,
        B = 0x2,
        C = 0x4,
        _,
    };

    const value: MyEnum = @enumFromInt(@intFromEnum(MyEnum.A) | @intFromEnum(MyEnum.B));
    try std.testing.expectEqual(true, enumHasAnyFlags(value, &.{ MyEnum.A, MyEnum.C }));
    try std.testing.expectEqual(false, enumHasAnyFlags(value, &.{MyEnum.C}));
}
