const std = @import("std");

pub const ExcelSheetType = enum(u8) {
    default = 0x1,
    sub_rows = 0x2,
};

pub const ExcelHeaderHeader = extern struct {
    const expected_magic = "EXHF";

    magic: [4]u8 align(1),
    version: u16 align(1),
    data_offset: u16 align(1),
    column_count: u16 align(1),
    page_count: u16 align(1),
    language_count: u16 align(1),

    _padding0: [3]u8 align(1),

    sheet_type: ExcelSheetType align(1),

    _padding1: [2]u8 align(1),

    row_count: u32 align(1),

    _padding2: [8]u8 align(1),

    pub fn validateMagic(self: *ExcelHeaderHeader) !void {
        if (!std.mem.eql(u8, expected_magic, &self.magic)) {
            return error.InvalidMagic;
        }
    }
};

pub const ExcelColumnType = enum(u16) {
    const Self = @This();

    string = 0x0,

    bool = 0x1,

    i8 = 0x2,
    u8 = 0x3,
    i16 = 0x4,
    u16 = 0x5,
    i32 = 0x6,
    u32 = 0x7,

    f32 = 0x9,

    i64 = 0xA,
    u64 = 0xB,

    packed_bool0 = 0x19,
    packed_bool1 = 0x1A,
    packed_bool2 = 0x1B,
    packed_bool3 = 0x1C,
    packed_bool4 = 0x1D,
    packed_bool5 = 0x1E,
    packed_bool6 = 0x1F,
    packed_bool7 = 0x20,

    pub fn packedBoolMask(self: Self) !u8 {
        return switch (self) {
            .packed_bool0 => 0x01,
            .packed_bool1 => 0x02,
            .packed_bool2 => 0x04,
            .packed_bool3 => 0x08,
            .packed_bool4 => 0x10,
            .packed_bool5 => 0x20,
            .packed_bool6 => 0x40,
            .packed_bool7 => 0x80,
            else => return error.InvalidPackedBool,
        };
    }
};

pub const ExcelColumnDefinition = extern struct {
    column_type: ExcelColumnType align(1),
    offset: u16 align(1),
};

pub const ExcelPageDefinition = extern struct {
    start_id: u32 align(1),
    row_count: u32 align(1),
};

pub const ExcelDataHeader = extern struct {
    const expected_magic = "EXDF";

    magic: [4]u8 align(1),
    version: u16 align(1),
    _padding0: [2]u8 align(1),
    index_size: u32 align(1),
    _padding1: [20]u8 align(1),

    pub fn validateMagic(self: *ExcelDataHeader) !void {
        if (!std.mem.eql(u8, expected_magic, &self.magic)) {
            return error.InvalidMagic;
        }
    }
};

pub const ExcelDataOffset = extern struct {
    row_id: u32 align(1),
    offset: u32 align(1),
};

pub const ExcelDataRowPreamble = extern struct {
    data_size: u32 align(1),
    row_count: u16 align(1),
};
