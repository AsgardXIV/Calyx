const std = @import("std");
const Allocator = std.mem.Allocator;

const ExcelList = @This();

const Magic = "EXLT";
const LineDelimiter = "\r\n";

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

allocator: Allocator,
version: u32,
sheet_names: std.ArrayListUnmanaged([]const u8),
id_to_key: std.AutoHashMapUnmanaged(u32, []const u8),

pub fn init(allocator: Allocator, bsr: *BufferedStreamReader) !*ExcelList {
    const list = try allocator.create(ExcelList);
    errdefer allocator.destroy(list);

    list.* = .{
        .allocator = allocator,
        .version = 0,
        .sheet_names = .{},
        .id_to_key = .{},
    };

    try list.populate(bsr);

    return list;
}

pub fn deinit(list: *ExcelList) void {
    list.cleanupSheetNames();
    list.allocator.destroy(list);
}

/// Get the ID for a given sheet key.
pub fn getKeyForId(list: *ExcelList, id: u32) ?[]const u8 {
    return list.id_to_key.get(id) orelse null;
}

/// Check if the list contains a sheet with the given name.
pub fn hasSheet(list: *ExcelList, sheet_name: []const u8) bool {
    for (list.sheet_names.items) |name| {
        if (std.mem.eql(u8, name, sheet_name)) return true;
    }
    return false;
}

fn populate(list: *ExcelList, bsr: *BufferedStreamReader) !void {
    const reader = bsr.reader();

    var sfb = std.heap.stackFallback(2048, list.allocator);
    const sfa = sfb.get();

    // Read the header
    const raw_header = try readExlLine(sfa, reader.any());
    {
        errdefer sfa.free(raw_header);

        // Read and split the header
        var header_parts = std.mem.splitScalar(u8, raw_header, ',');
        const magic_str = header_parts.next() orelse return error.InvalidHeader;
        const version_str = header_parts.next() orelse return error.InvalidHeader;

        // Validate
        if (!std.mem.eql(u8, magic_str, Magic)) return error.InvalidMagic;
        list.version = try std.fmt.parseInt(u32, version_str, 10);
    }
    sfa.free(raw_header);

    // Read all lines
    errdefer list.cleanupSheetNames();
    while (true) {
        const line = readExlLine(sfa, reader.any()) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        defer sfa.free(line);
        try list.processEntryLine(line);
    }
}

fn readExlLine(allocator: Allocator, reader: std.io.AnyReader) ![]const u8 {
    const line = try reader.readUntilDelimiterAlloc(allocator, '\r', 1024);
    const next_byte = try reader.readByte();
    if (next_byte != '\n') {
        return error.InvalidLineEnd;
    }
    return line;
}

fn processEntryLine(list: *ExcelList, line: []const u8) !void {
    // Split the line by comma
    var parts = std.mem.splitScalar(u8, line, ',');
    const name = parts.next() orelse return error.InvalidEntry;
    if (name.len == 0) return error.InvalidEntry;
    const id_str = parts.next() orelse return error.InvalidEntry;

    // Allocate a heap string for the name
    const heap_str = try list.allocator.dupe(u8, name);
    errdefer list.allocator.free(heap_str);

    // Add to list
    try list.sheet_names.append(list.allocator, heap_str);
    errdefer _ = list.sheet_names.pop();

    // Parse the ID
    const id = try std.fmt.parseInt(i32, id_str, 10);

    // Negative (-1) is a special case for "no ID"
    if (id >= 0) {
        // Add to id to key map
        try list.id_to_key.putNoClobber(list.allocator, @intCast(id), heap_str);
    }
}

fn cleanupSheetNames(list: *ExcelList) void {
    // Free the sheet names first
    for (list.sheet_names.items) |sheet_name| {
        list.allocator.free(sheet_name);
    }

    // Free the list
    list.sheet_names.deinit(list.allocator);

    // Free the hash map
    list.id_to_key.deinit(list.allocator);
}

test "excelListTests" {

    // Valid file
    {
        const content = "EXLT,1337\r\nEmetWasRight,123\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const list = try ExcelList.init(std.testing.allocator, &stream);
        defer list.deinit();

        // Version
        try std.testing.expectEqual(list.version, 1337);

        // Check the mapping
        const expected_key = "EmetWasRight";
        const actual_key = list.getKeyForId(123);
        try std.testing.expectEqualStrings(expected_key, actual_key.?);
    }

    // No ID key
    {
        const content = "EXLT,1337\r\nEmetWasRight,-1\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const list = try ExcelList.init(std.testing.allocator, &stream);
        defer list.deinit();
        // Check the mapping
        const expected_key = "EmetWasRight";
        try std.testing.expect(list.hasSheet(expected_key));
    }

    // Invalid magic
    {
        const content = "INVALID_MAGIC,1337\r\nEmetWasRight,123\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Invalid header
    {
        const content = "Blahblah\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Invalid Version
    {
        const content = "Blahblah,notanum\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Missing value
    {
        const content = "EXLT,1337\r\nEmetWasRight\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Blank value
    {
        const content = "EXLT,1337\r\nEmetWasRight,\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Blank key
    {
        const content = "EXLT,1337\r\n,123\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Invalid value
    {
        const content = "EXLT,1337\r\nEmetWasRight,notanum\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Bad line end
    {
        const content = "EXLT,1337\rEmetWasRight,123\r\n";
        var stream = BufferedStreamReader.initFromConstBuffer(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }
}
