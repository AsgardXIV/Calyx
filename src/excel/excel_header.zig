const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SheetType = enum(u8) {
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

    sheet_type: SheetType,

    _padding1: [2]u8,

    row_count: u32,

    _padding2: [8]u8,

    pub fn validate(self: *ExcelHeaderHeader) !void {
        if (!std.mem.eql(u8, Magic, &self.magic)) {
            return error.InvalidMagic;
        }
    }
};

pub const ExcelHeader = struct {
    const Self = @This();

    allocator: Allocator,
    header: ExcelHeaderHeader,

    pub fn init(allocator: Allocator, stream: *std.io.FixedBufferStream([]const u8)) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        try self.populate(stream);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn populate(self: *Self, stream: *std.io.FixedBufferStream([]const u8)) !void {
        const reader = stream.reader();

        self.header = try reader.readStructEndian(ExcelHeaderHeader, .big);
        try self.header.validate();
    }
};
