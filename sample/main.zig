const std = @import("std");
const calyx = @import("calyx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer = try calyx.core.io.BufferedStreamReader.initFromPath("D:\\test.txt");
    const reader = buffer.reader();
    const first_byte = try reader.readByte();
    std.log.info("First byte: {d}", .{first_byte});
    buffer.close();

    const raw = "hello, world!";
    var buffer2 = calyx.core.io.BufferedStreamReader.initFromFixedBuffer(raw);
    const reader2 = buffer2.reader();
    const first_byte2 = try reader2.readByte();

    std.log.info("First byte: {d}", .{first_byte2});

    _ = allocator;
}
