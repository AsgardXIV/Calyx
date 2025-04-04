const std = @import("std");
const fs = std.fs;
const io = std.io;

pub fn BufferedFileReader(comptime buffer_size: usize) type {
    return struct {
        const Self = @This();

        pub const Reader = std.io.Reader(*Self, anyerror, Self.readFn);

        file: std.fs.File,
        buffered: std.io.BufferedReader(buffer_size, std.fs.File.Reader),
        position: u64,

        pub fn init(path: []const u8) !Self {
            const file = try fs.openFileAbsolute(path, .{ .mode = .read_only });
            return .{
                .file = file,
                .buffered = .{
                    .unbuffered_reader = file.reader(),
                },
                .position = 0,
            };
        }

        fn readFn(self: *Self, dest: []u8) !usize {
            const n = try self.buffered.reader().read(dest);
            self.position += n;
            return n;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn seekTo(self: *Self, pos: u64) !void {
            if (self.position == pos) {
                return;
            }

            try self.file.seekTo(pos);
            self.buffered = .{
                .unbuffered_reader = self.file.reader(),
            };
            self.position = pos;
        }

        pub fn getPos(self: *Self) u64 {
            return self.position;
        }

        pub fn close(self: *Self) void {
            self.file.close();
        }
    };
}
