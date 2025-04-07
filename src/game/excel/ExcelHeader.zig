const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelHeaderHeader = native_types.ExcelHeaderHeader;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelHeader = @This();

allocator: Allocator,
header: ExcelHeaderHeader,

pub fn init(allocator: Allocator, bsr: *BufferedStreamReader) !*ExcelHeader {
    const header = try allocator.create(ExcelHeader);
    errdefer allocator.destroy(header);

    header.* = .{
        .allocator = allocator,
        .header = .{},
    };

    try header.populate(bsr);

    return header;
}

pub fn deinit(header: *ExcelHeader) void {
    header.allocator.destroy(header);
}

fn populate(header: *ExcelHeader, bsr: *BufferedStreamReader) !void {
    const reader = bsr.reader();

    // Read the header
    header.header = try reader.readStruct(ExcelHeaderHeader);
    try header.header.validateMagic();
}
