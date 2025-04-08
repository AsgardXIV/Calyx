const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelDataHeader = native_types.ExcelDataHeader;
const ExcelDataOffset = native_types.ExcelDataOffset;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelDataFile = @This();

allocator: Allocator,
header: ExcelDataHeader,
indexes: []ExcelDataOffset,
data_start: u32,
raw_sheet_data: []const u8,

pub fn init(allocator: Allocator, bsr: *BufferedStreamReader) !*ExcelDataFile {
    const data = try allocator.create(ExcelDataFile);
    errdefer allocator.destroy(data);

    data.* = .{
        .allocator = allocator,
        .header = undefined,
        .indexes = undefined,
        .raw_sheet_data = undefined,
        .data_start = undefined,
    };

    try data.populate(bsr);

    return data;
}

pub fn deinit(data: *ExcelDataFile) void {
    data.allocator.free(data.indexes);
    data.allocator.free(data.raw_sheet_data);
    data.allocator.destroy(data);
}

fn populate(data: *ExcelDataFile, bsr: *BufferedStreamReader) !void {
    const reader = bsr.reader();

    // Read the header
    data.header = try reader.readStructEndian(ExcelDataHeader, .big);
    try data.header.validateMagic();

    // Index count
    const index_count = data.header.index_size / @sizeOf(ExcelDataOffset);

    // Read the indexes
    data.indexes = try data.allocator.alloc(ExcelDataOffset, index_count);
    errdefer data.allocator.free(data.indexes);
    for (data.indexes) |*entry| {
        entry.* = try reader.readStructEndian(ExcelDataOffset, .big);
    }

    // We need this to adjust offsets later
    data.data_start = @intCast(try bsr.getPos());

    // Read until EOF
    const data_size = try bsr.getRemaining();
    const buffer = try data.allocator.alloc(u8, data_size);
    errdefer data.allocator.free(data.raw_sheet_data);
    _ = try reader.readAll(buffer);
    data.raw_sheet_data = buffer;
}
