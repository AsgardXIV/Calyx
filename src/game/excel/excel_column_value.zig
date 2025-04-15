const native_types = @import("native_types.zig");
const ExcelColumnType = native_types.ExcelColumnType;

pub const ExcelColumnValue = union(enum) {
    string: []const u8,

    bool: bool,

    i8: i8,
    u8: u8,

    i16: i16,
    u16: u16,

    i32: i32,
    u32: u32,

    f32: f32,

    i64: i64,
    u64: u64,
};
