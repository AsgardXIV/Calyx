const std = @import("std");
const io = std.io;

// TODO: Zig is replacing the io stuff, see https://github.com/ziglang/zig/tree/wrangle-writer-buffering
// We should be using the new stuff once it lands instead of this janky solution

const Self = @This();

pub const Reader = io.Reader(*Self, anyerror, read);

file: std.fs.File,
buffer: io.BufferedReader(4096, std.fs.File.Reader),
pos: u64,

pub fn initFromPath(path: []const u8) !Self {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    return initFromFile(file);
}

pub fn initFromFile(in_file: std.fs.File) Self {
    return .{
        .file = in_file,
        .buffer = std.io.bufferedReader(in_file.reader()),
        .pos = 0,
    };
}

pub fn read(self: *Self, dest: []u8) !usize {
    const n = try self.buffer.read(dest);
    self.pos += n;
    return n;
}

pub fn seekTo(self: *Self, pos: u64) !void {
    try self.file.seekTo(pos);
    self.pos = pos;
    self.buffer = .{
        .unbuffered_reader = self.file.reader(),
    };
}

pub fn close(self: *Self) void {
    self.file.close();
}

pub fn getPos(self: *Self) !u64 {
    return self.pos;
}

pub fn getEndPos(self: *Self) !u64 {
    return self.file.getEndPos();
}

pub fn getRemaining(self: *Self) !u64 {
    const end = try self.getEndPos();
    const pos = try self.getPos();
    return end - pos;
}

pub fn reader(self: *Self) Reader {
    return .{ .context = self };
}

test "basic file read first byte" {
    const file = try std.fs.cwd().openFile("src/test/assets/basic_file.txt", .{ .mode = .read_only });
    var buffer = Self.initFromFile(file);
    const rdr = buffer.reader();
    const first_byte = try rdr.readByte();
    try std.testing.expectEqual(first_byte, 'H');
}

test "basic file seek" {
    const file = try std.fs.cwd().openFile("src/test/assets/basic_file.txt", .{ .mode = .read_only });
    var buffer = Self.initFromFile(file);
    const rdr = buffer.reader();

    {
        try buffer.seekTo(7);
        const first_byte = try rdr.readByte();
        try std.testing.expectEqual(first_byte, 'W');
    }

    {
        try buffer.seekTo(1);
        const first_byte = try rdr.readByte();
        try std.testing.expectEqual(first_byte, 'e');
    }
}

test "basic file pos" {
    const file = try std.fs.cwd().openFile("src/test/assets/basic_file.txt", .{ .mode = .read_only });
    var buffer = Self.initFromFile(file);
    const skip_bytes = 4;
    const rdr = buffer.reader();

    try rdr.skipBytes(skip_bytes, .{});
    try std.testing.expectEqual(buffer.getPos(), skip_bytes);
}

test "basic file endPos" {
    const file = try std.fs.cwd().openFile("src/test/assets/basic_file.txt", .{ .mode = .read_only });
    var buffer = Self.initFromFile(file);
    try std.testing.expectEqual(buffer.getEndPos(), 13);
}

test "basic file remaining" {
    const file = try std.fs.cwd().openFile("src/test/assets/basic_file.txt", .{ .mode = .read_only });
    var buffer = Self.initFromFile(file);
    const skip_bytes = 4;
    const rdr = buffer.reader();

    try rdr.skipBytes(skip_bytes, .{});

    try std.testing.expectEqual(buffer.getRemaining(), 13 - skip_bytes);
}
