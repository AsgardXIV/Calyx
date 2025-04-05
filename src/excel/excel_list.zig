const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ExcelList = struct {
    const magic = "EXLT";
    const line_delimiter = "\r\n";

    const Self = @This();

    allocator: Allocator,
    version: u32,
    id_to_key: std.AutoArrayHashMapUnmanaged(i32, []const u8),
    key_to_id: std.StringHashMapUnmanaged(i32),

    pub fn init(allocator: Allocator, stream: *std.io.FixedBufferStream([]const u8)) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .version = 0,
            .id_to_key = .{},
            .key_to_id = .{},
        };

        try self.populate(stream);

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Free the sheet names first
        var key_iter = self.key_to_id.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }

        // Free the hash maps
        self.id_to_key.deinit(self.allocator);
        self.key_to_id.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Get the key for a given sheet ID.
    /// Returned value is only valid until the `ExcelList` is deinitialized.
    pub fn getKeyForId(self: *Self, id: i32) ?[]const u8 {
        return self.id_to_key.get(id) orelse null;
    }

    /// Get the ID for a given sheet key.
    pub fn getIdForKey(self: *Self, key: []const u8) ?i32 {
        return self.key_to_id.get(key) orelse null;
    }

    fn populate(self: *Self, stream: *std.io.FixedBufferStream([]const u8)) !void {
        const reader = stream.reader();

        var sfb = std.heap.stackFallback(2048, self.allocator);
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
            if (!std.mem.eql(u8, magic_str, magic)) return error.InvalidMagic;
            self.version = try std.fmt.parseInt(u32, version_str, 10);
        }
        sfa.free(raw_header);

        // Read all lines
        while (true) {
            const line = readExlLine(sfa, reader.any()) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            defer sfa.free(line);
            try self.processEntryLine(line);
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

    fn processEntryLine(self: *Self, line: []const u8) !void {
        // Split the line by comma
        var parts = std.mem.splitScalar(u8, line, ',');
        const name = parts.next() orelse return error.InvalidEntry;
        if (name.len == 0) return error.InvalidEntry;
        const id_str = parts.next() orelse return error.InvalidEntry;

        // Parse the ID
        const id = try std.fmt.parseInt(i32, id_str, 10);

        // Allocate a heap string for the name
        const heap_str = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(heap_str);

        // Add to id to key map
        try self.id_to_key.put(self.allocator, id, heap_str);

        // Add to key to id map
        try self.key_to_id.put(self.allocator, heap_str, id);
    }
};

test "excelListTests" {

    // Valid file
    {
        const content = "EXLT,1337\r\nEmetWasRight,123\r\n";
        var stream = std.io.fixedBufferStream(content);
        const list = try ExcelList.init(std.testing.allocator, &stream);
        defer list.deinit();

        // Version
        try std.testing.expectEqual(list.version, 1337);

        // Check the mapping
        const expected_key = "EmetWasRight";
        const expected_id = 123;
        const actual_key = list.getKeyForId(expected_id);
        const actual_id = list.getIdForKey(expected_key);
        try std.testing.expectEqualStrings(expected_key, actual_key.?);
        try std.testing.expectEqual(expected_id, actual_id.?);
    }

    // Invalid magic
    {
        const content = "INVALID_MAGIC,1337\r\nEmetWasRight,123\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Invalid header
    {
        const content = "Blahblah\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Invalid Version
    {
        const content = "Blahblah,notanum\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Missing value
    {
        const content = "EXLT,1337\r\nEmetWasRight\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Blank value
    {
        const content = "EXLT,1337\r\nEmetWasRight,\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Blank key
    {
        const content = "EXLT,1337\r\n,123\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Invalid value
    {
        const content = "EXLT,1337\r\nEmetWasRight,notanum\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }

    // Bad line end
    {
        const content = "EXLT,1337\rEmetWasRight,123\r\n";
        var stream = std.io.fixedBufferStream(content);
        const result = ExcelList.init(std.testing.allocator, &stream) catch null;
        try std.testing.expectEqual(null, result);
    }
}
