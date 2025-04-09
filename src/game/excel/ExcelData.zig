const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelDataHeader = native_types.ExcelDataHeader;
const ExcelDataOffset = native_types.ExcelDataOffset;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelData = @This();

allocator: Allocator,
header: ExcelDataHeader,
indexes: []ExcelDataOffset,
data_start: u32,
raw_sheet_data: []const u8,
row_to_index: std.AutoHashMapUnmanaged(u32, usize),

pub fn init(allocator: Allocator, bsr: *BufferedStreamReader) !*ExcelData {
    const data = try allocator.create(ExcelData);
    errdefer allocator.destroy(data);

    data.* = .{
        .allocator = allocator,
        .header = undefined,
        .indexes = undefined,
        .raw_sheet_data = undefined,
        .data_start = undefined,
        .row_to_index = .{},
    };

    try data.populate(bsr);

    return data;
}

pub fn deinit(data: *ExcelData) void {
    data.row_to_index.deinit(data.allocator);
    data.allocator.free(data.indexes);
    data.allocator.free(data.raw_sheet_data);
    data.allocator.destroy(data);
}

fn populate(data: *ExcelData, bsr: *BufferedStreamReader) !void {
    const reader = bsr.reader();

    // Read the header
    data.header = try reader.readStructEndian(ExcelDataHeader, .big);
    try data.header.validateMagic();

    // Index count
    const index_count = data.header.index_size / @sizeOf(ExcelDataOffset);

    // Allocate space for the map
    try data.row_to_index.ensureTotalCapacity(data.allocator, index_count);
    errdefer data.row_to_index.deinit(data.allocator);

    // Read the indexes
    data.indexes = try data.allocator.alloc(ExcelDataOffset, index_count);
    errdefer data.allocator.free(data.indexes);
    var i: usize = 0;
    for (data.indexes) |*entry| {
        entry.* = try reader.readStructEndian(ExcelDataOffset, .big);
        data.row_to_index.putAssumeCapacity(entry.row_id, i);
        i += 1;
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
