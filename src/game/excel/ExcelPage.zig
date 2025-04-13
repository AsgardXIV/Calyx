const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelDataHeader = native_types.ExcelDataHeader;
const ExcelDataOffset = native_types.ExcelDataOffset;

const FixedBufferStream = std.io.FixedBufferStream([]const u8);

const ExcelPage = @This();

allocator: Allocator,
header: ExcelDataHeader,
indexes: []ExcelDataOffset,
data_start: u32,
raw_sheet_data: []const u8,
row_to_index: std.AutoHashMapUnmanaged(u32, usize),

pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !*ExcelPage {
    const data = try allocator.create(ExcelPage);
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

pub fn deinit(page: *ExcelPage) void {
    page.row_to_index.deinit(page.allocator);
    page.allocator.free(page.indexes);
    page.allocator.free(page.raw_sheet_data);
    page.allocator.destroy(page);
}

fn populate(page: *ExcelPage, fbs: *FixedBufferStream) !void {
    const reader = fbs.reader();

    // Read the header
    page.header = try reader.readStructEndian(ExcelDataHeader, .big);
    try page.header.validateMagic();

    // Index count
    const index_count = page.header.index_size / @sizeOf(ExcelDataOffset);

    // Allocate space for the map
    try page.row_to_index.ensureTotalCapacity(page.allocator, index_count);
    errdefer page.row_to_index.deinit(page.allocator);

    // Read the indexes
    page.indexes = try page.allocator.alloc(ExcelDataOffset, index_count);
    errdefer page.allocator.free(page.indexes);
    for (page.indexes, 0..) |*entry, i| {
        entry.* = try reader.readStructEndian(ExcelDataOffset, .big);
        page.row_to_index.putAssumeCapacity(entry.row_id, i);
    }

    // We need this to adjust offsets later
    page.data_start = @intCast(try fbs.getPos());

    // Read until EOF
    const remaining = try fbs.getEndPos() - try fbs.getPos();
    const buffer = try page.allocator.alloc(u8, remaining);
    errdefer page.allocator.free(page.raw_sheet_data);
    _ = try reader.readAll(buffer);
    page.raw_sheet_data = buffer;
}
