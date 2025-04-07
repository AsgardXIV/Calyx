const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelDataHeader = native_types.ExcelDataHeader;
const ExcelDataOffset = native_types.ExcelDataOffset;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelDataFile = @This();

allocator: Allocator,
header: ExcelDataHeader,

pub fn init(allocator: Allocator, bsr: *BufferedStreamReader) !*ExcelDataFile {
    const data = try allocator.create(ExcelDataFile);
    errdefer allocator.destroy(data);

    data.* = .{
        .allocator = allocator,
        .header = undefined,
    };

    try data.populate(bsr);

    return data;
}

pub fn deinit(data: *ExcelDataFile) void {
    data.allocator.destroy(data);
}

fn populate(data: *ExcelDataFile, bsr: *BufferedStreamReader) !void {
    const reader = bsr.reader();

    // Read the header
    data.header = try reader.readStructEndian(ExcelDataHeader, .big);
    try data.header.validateMagic();
}
