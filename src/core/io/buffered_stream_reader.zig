const std = @import("std");

pub const BufferedStreamReader = union(enum) {
    const Self = @This();

    file: FileBufferedStreamReader,
    fixed_buffer: FixedBufferedStreamReader,

    pub fn initFromPath(path: []const u8) !Self {
        const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
        return initFromFile(file);
    }

    pub fn initFromFile(in_file: std.fs.File) Self {
        var buffered_reader = FileBufferedStreamReader.BufferedReader{
            .unbuffered_reader = in_file.reader(),
        };

        return Self{
            .file = .{
                .file_handle = in_file,
                .buffered = buffered_reader,
                .position = 0,
                .reader = buffered_reader.reader().any(),
                .seeker = in_file.seekableStream(),
            },
        };
    }

    pub fn initFromFixedBuffer(buffer: []const u8) Self {
        var fixed_buffer = std.io.fixedBufferStream(buffer);

        return Self{
            .fixed_buffer = .{
                .buffer = buffer,
                .fixed_buffer = fixed_buffer,
                .position = 0,
                .reader = fixed_buffer.reader().any(),
                .seeker = fixed_buffer.seekableStream(),
            },
        };
    }

    pub fn reader(self: *const Self) std.io.AnyReader {
        return switch (self.*) {
            .file => |*file| file.reader,
            .fixed_buffer => |*fixed_buffer| fixed_buffer.reader,
        };
    }

    pub fn seekTo(self: *Self, offset: u64) !void {
        switch (self.*) {
            .file => |*file| {
                if (offset == file.position) return;
                try file.seeker.seekTo(offset);
                file.position = offset;
                file.buffered = .{
                    .unbuffered_reader = file.file_handle.reader(),
                };
            },
            .fixed_buffer => |*fixed_buffer| {
                if (offset == fixed_buffer.position) return;
                try fixed_buffer.seeker.seekTo(offset);
                fixed_buffer.position = offset;
            },
        }
    }

    pub fn getPos(self: *const Self) u64 {
        return switch (self.*) {
            .file => |*file| file.position,
            .fixed_buffer => |*fixed_buffer| fixed_buffer.position,
        };
    }

    pub fn close(self: *Self) void {
        switch (self.*) {
            .file => |*file| file.file_handle.close(),
            .fixed_buffer => {},
        }
    }

    fn readFn(self: *Self, dest: []u8) !usize {
        const n = switch (self.*) {
            .file => |*file| try file.reader.read(dest),
        };
        self.position += n;
        return n;
    }
};

const FileBufferedStreamReader = struct {
    pub const BufferedReader = std.io.BufferedReader(4096, std.fs.File.Reader);

    file_handle: std.fs.File,
    buffered: BufferedReader,
    reader: std.io.AnyReader,
    seeker: std.fs.File.SeekableStream,
    position: u64,
};

const FixedBufferedStreamReader = struct {
    pub const FixedBufferType = std.io.FixedBufferStream([]const u8);

    buffer: []const u8,
    fixed_buffer: FixedBufferType,
    reader: std.io.AnyReader,
    seeker: FixedBufferType.SeekableStream,
    position: u64,
};

test "basic fixed read first byte" {
    const raw = "hello, world!";
    var buffer = BufferedStreamReader.initFromFixedBuffer(raw);
    const reader = buffer.reader();
    const first_byte = try reader.readByte();
    try std.testing.expectEqual(first_byte, 'h');
}

test "basic fixed seek" {
    const raw = "hello, world!";
    var buffer = BufferedStreamReader.initFromFixedBuffer(raw);
    const reader = buffer.reader();
    try buffer.seekTo(7);
    const first_byte = try reader.readByte();
    try std.testing.expectEqual(first_byte, 'w');
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
    try buffer.seekTo(7);
    const first_byte = try reader.readByte();
    try std.testing.expectEqual(first_byte, 'W');
}
