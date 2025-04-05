const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ExcelList = struct {
    const magic = "EXLT";
    const line_delimiter = "\r\n";

    const Self = @This();

    allocator: Allocator,
    version: u32,

    pub fn init(allocator: Allocator, stream: *std.io.FixedBufferStream([]const u8)) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .version = 1,
        };

        try self.populate(stream);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
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
            // TODO: Parse it
            std.log.info("LINE: {s}", .{line});
        }
    }

    fn readExlLine(allocator: Allocator, reader: std.io.AnyReader) ![]const u8 {
        const line = try reader.readUntilDelimiterAlloc(allocator, '\r', 1024);
        try reader.skipBytes(1, .{});
        return line;
    }
};

test "excelListTests" {
    {
        const content = "EXLT,1337\r\nEmetWasRight,123\r\n";
        var stream = std.io.fixedBufferStream(content);
        const list = try ExcelList.init(std.testing.allocator, &stream);
        defer list.deinit();

        try std.testing.expectEqual(list.version, 1337);
    }
}
