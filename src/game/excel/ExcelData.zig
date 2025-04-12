const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelDataHeader = native_types.ExcelDataHeader;
const ExcelDataOffset = native_types.ExcelDataOffset;

const FixedBufferStream = std.io.FixedBufferStream([]const u8);

const ExcelData = @This();

allocator: Allocator,
header: ExcelDataHeader,
indexes: []ExcelDataOffset,
data_start: u32,
raw_sheet_data: []const u8,
row_to_index: std.AutoHashMapUnmanaged(u32, usize),

pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !*ExcelData {
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

    try data.populate(fbs);

    return data;
}

pub fn deinit(data: *ExcelData) void {
    data.row_to_index.deinit(data.allocator);
    data.allocator.free(data.indexes);
    data.allocator.free(data.raw_sheet_data);
    data.allocator.destroy(data);
}

fn populate(data: *ExcelData, fbs: *FixedBufferStream) !void {
    const reader = fbs.reader();

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
    for (data.indexes, 0..) |*entry, i| {
        entry.* = try reader.readStructEndian(ExcelDataOffset, .big);
        data.row_to_index.putAssumeCapacity(entry.row_id, i);
    }

    // We need this to adjust offsets later
    data.data_start = @intCast(try fbs.getPos());

    // Read until EOF
    const remaining = try fbs.getEndPos() - try fbs.getPos();
    const buffer = try data.allocator.alloc(u8, remaining);
    errdefer data.allocator.free(data.raw_sheet_data);
    _ = try reader.readAll(buffer);
    data.raw_sheet_data = buffer;
}
