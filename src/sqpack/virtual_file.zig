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
    _,
};

pub const VirtualFileInfo = extern struct {
    size: u32,
    file_type: VirtualFileType,
    raw_file_size: u32,
    _padding0: u32,
    _padding1: u32,
    num_of_blocks: u32,
};

pub const DatBlockInfo = extern struct {
    offset: u32,
    compressed_size: u16,
    uncompressed_size: u16,
};

pub const DatBlockType = enum(u32) {
    compressed = 16000,
    uncompressed = 32000,
    _,
};

pub const DatBlockHeader = extern struct {
    size: u32,
    _padding0: u32,
    block_type: DatBlockType,
    data_size: u32,
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

        try self.mountDatFile();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
        self.allocator.destroy(self);
    }

    pub fn readFile(self: *Self, allocator: Allocator, offset: u64) ![]const u8 {
        try self.file.seekTo(offset);

        const reader = self.file.reader();

        const file_info = try reader.readStruct(VirtualFileInfo);

        const raw_bytes = try allocator.alloc(u8, file_info.raw_file_size);
        errdefer allocator.free(raw_bytes);

        var stream = std.io.fixedBufferStream(raw_bytes);

        switch (file_info.file_type) {
            .empty => {},
            .standard => try self.readStandardFile(offset, file_info, &stream),
            .model => {},
            .texture => {},
            else => return error.InvalidFileType,
        }

        return raw_bytes;
    }

    fn readStandardFile(self: *Self, base_offset: u64, file_info: VirtualFileInfo, buffer: *std.io.FixedBufferStream([]u8)) !void {
        const reader = self.file.reader();

        const block_count = file_info.num_of_blocks;

        const blocks = try self.allocator.alloc(DatBlockInfo, block_count);
        defer self.allocator.free(blocks);

        for (blocks) |*block| {
            block.* = try reader.readStruct(DatBlockInfo);
        }

        for (blocks) |*block| {
            const calculated_offset = base_offset + file_info.size + block.offset;
            try self.readFileBlock(calculated_offset, buffer);
        }
    }

    fn readFileBlock(self: *Self, offset: u64, buffer: *std.io.FixedBufferStream([]u8)) !void {
        try self.file.seekTo(offset);

        const reader = self.file.reader();
        const block_header = try reader.readStruct(DatBlockHeader);

        if (block_header.block_type == .uncompressed) {
            _ = try reader.readAll(buffer.buffer[buffer.pos .. buffer.pos + block_header.data_size]);
            buffer.pos += block_header.data_size;
        } else {
            // TODO: Decompress here?
        }
    }

    fn mountDatFile(self: *Self) !void {
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
