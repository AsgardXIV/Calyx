const std = @import("std");

const Allocator = std.mem.Allocator;

const Chunk = @import("chunk.zig").Chunk;

const path_utils = @import("path_utils.zig");
const PathUtils = path_utils.PathUtils;

pub const VirtualFileType = enum(u32) {
    empty = 0x1,
    standard = 0x2,
    model = 0x3,
    texture = 0x4,
};

pub const VirtualFileInfo = extern struct {
    size: u32,
    file_type: VirtualFileType,
    raw_file_size: u32,
    _padding0: u16,
    num_of_blocks: u32,
};

pub const DatFile = struct {
    const Self = @This();

    allocator: Allocator,
    chunk: *Chunk,
    file_id: u8,
    file: std.fs.File,

    pub fn init(allocator: Allocator, chunk: *Chunk, file_id: u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .chunk = chunk,
            .file_id = file_id,
            .file = undefined,
        };

        try self.mount_file();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
        self.allocator.destroy(self);
    }

    pub fn load_file(self: *Self, offset: u64) !void {
        try self.file.seekTo(offset);

        const reader = self.file.reader();

        const file_info = try reader.readStruct(VirtualFileInfo);

        std.log.err("Type: {d}", .{@intFromEnum(file_info.file_type)});
    }

    fn mount_file(self: *Self) !void {
        const file_name = try PathUtils.buildSqPackFileNameTyped(self.allocator, .{
            .platform = self.chunk.category.repository.pack.game_data.platform,
            .repo_id = self.chunk.category.repository.repo_id,
            .category_id = self.chunk.category.category_id,
            .chunk_id = self.chunk.chunk_id,
            .file_type = .dat,
            .file_idx = self.file_id,
        });
        defer self.allocator.free(file_name);

        const file_path = try std.fs.path.join(self.allocator, &.{ self.chunk.category.repository.repo_path, file_name });
        defer self.allocator.free(file_path);

        self.file = try std.fs.openFileAbsolute(file_path, .{ .mode = .read_only });
    }
};
