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

    pub fn validate(self: *ExcelHeaderHeader) !void {
        if (!std.mem.eql(u8, Magic, &self.magic)) {
            return error.InvalidMagic;
        }
    }
};
