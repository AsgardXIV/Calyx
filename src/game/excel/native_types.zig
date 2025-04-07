const std = @import("std");

pub const ExcelSheetType = enum(u8) {
    Unknown,
    Default,
    SubRows,
};

pub const ExcelHeaderHeader = extern struct {
    const Magic = "EXHF";

    magic: [4]u8,
    version: u16,
    data_offset: u16,
    column_count: u16,
    page_count: u16,
    language_count: u16,

    _padding0: [3]u8,

    sheet_type: ExcelSheetType,

    _padding1: [2]u8,

    row_count: u32,

    _padding2: [8]u8,

    pub fn validateMagic(self: *ExcelHeaderHeader) !void {
        if (!std.mem.eql(u8, Magic, &self.magic)) {
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

    _,

    pub fn isPackedBool(self: Self) bool {
        const current_value = @intFromEnum(self);
        const packed_bool0 = @intFromEnum(Self.packed_bool0);
        const packed_bool7 = @intFromEnum(Self.packed_bool7);
        return current_value >= packed_bool0 and current_value <= packed_bool7;
    }
};

pub const ExcelColumnDefinition = extern struct {
    column_type: ExcelColumnType,
    offset: u16,
};

pub const ExcelPageDefinition = extern struct {
    start_id: u32,
    row_count: u32,
};

pub const ExcelDataHeader = extern struct {
    const Magic = "EXDF";

    magic: [4]u8,
    version: u16,
    _padding0: [2]u8,
    index_size: u32,
    _padding1: [2]u8,

    pub fn validateMagic(self: *ExcelDataHeader) !void {
        if (!std.mem.eql(u8, Magic, &self.magic)) {
            return error.InvalidMagic;
        }
    }
};

pub const ExcelDataOffset = extern struct {
    row_id: u32,
    offset: u32,
};
