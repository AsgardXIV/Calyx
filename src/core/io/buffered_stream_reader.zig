const std = @import("std");
const io = std.io;

pub const BufferedStreamReader = union(enum) {
    const Self = @This();

    pub const Reader = io.Reader(*Self, anyerror, read);

    const_buffer: io.FixedBufferStream([]const u8),

    buffered_file: struct {
        file: std.fs.File,
        buffer: io.BufferedReader(4096, std.fs.File.Reader),
        pos: u64,
    },

    pub fn initFromPath(path: []const u8) !Self {
        const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
        return initFromFile(file);
    }

    pub fn initFromFile(in_file: std.fs.File) Self {
        return .{
            .buffered_file = .{
                .file = in_file,
                .buffer = std.io.bufferedReader(in_file.reader()),
                .pos = 0,
            },
        };
    }

    pub fn initFromConstBuffer(buffer: []const u8) Self {
        return .{
            .const_buffer = io.fixedBufferStream(buffer),
        };
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        switch (self.*) {
            .const_buffer => |*x| return x.read(dest),
            .buffered_file => |*x| return x.buffer.read(dest),
        }
    }

    pub fn seekTo(self: *Self, pos: u64) !void {
        switch (self.*) {
            .const_buffer => |*x| return x.seekTo(pos),
            .buffered_file => |*x| {
                try x.file.seekTo(pos);
                x.buffer = .{
                    .unbuffered_reader = x.file.reader(),
                };
                x.pos = pos;
            },
        }
    }

    pub fn close(self: *Self) void {
        switch (self.*) {
            .const_buffer => {},
            .buffered_file => |*x| x.file.close(),
        }
    }

    pub fn getPos(self: *Self) !u64 {
        switch (self.*) {
            .const_buffer => |*x| return x.getPos(),
            .buffered_file => |*x| return x.pos,
        }
    }

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};

test "basic fixed read first byte" {
    const raw = "hello, world!";
    var buffer = BufferedStreamReader.initFromConstBuffer(raw);
    const reader = buffer.reader();
    const first_byte = try reader.readByte();
    try std.testing.expectEqual(first_byte, 'h');
}

test "basic fixed seek" {
    const raw = "hello, world!";
    var buffer = BufferedStreamReader.initFromConstBuffer(raw);
    const reader = buffer.reader();

    {
        try buffer.seekTo(7);
        const first_byte = try reader.readByte();
        try std.testing.expectEqual(first_byte, 'w');
    }

    {
        try buffer.seekTo(1);
        const first_byte = try reader.readByte();
        try std.testing.expectEqual(first_byte, 'e');
    }
}

test "basic file read first byte" {
    const file = try std.fs.cwd().openFile("resources/tests/basic_file.txt", .{ .mode = .read_only });
    var buffer = BufferedStreamReader.initFromFile(file);
    const reader = buffer.reader();
    const first_byte = try reader.readByte();
    try std.testing.expectEqual(first_byte, 'H');
}

test "basic file seek" {
    const file = try std.fs.cwd().openFile("resources/tests/basic_file.txt", .{ .mode = .read_only });
    var buffer = BufferedStreamReader.initFromFile(file);
    const reader = buffer.reader();

    {
        try buffer.seekTo(7);
        const first_byte = try reader.readByte();
        try std.testing.expectEqual(first_byte, 'W');
    }

    {
        try buffer.seekTo(1);
        const first_byte = try reader.readByte();
        try std.testing.expectEqual(first_byte, 'e');
    }
}
