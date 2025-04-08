const native_types = @import("native_types.zig");
const ExcelColumnType = native_types.ExcelColumnType;

pub const ExcelColumnValue = union(ExcelColumnType) {
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

    packed_bool0: bool,
    packed_bool1: bool,
    packed_bool2: bool,
    packed_bool3: bool,
    packed_bool4: bool,
    packed_bool5: bool,
    packed_bool6: bool,
    packed_bool7: bool,
};
