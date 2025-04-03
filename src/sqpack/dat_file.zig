const std = @import("std");

const Allocator = std.mem.Allocator;

const Chunk = @import("chunk.zig").Chunk;

const path_utils = @import("path_utils.zig");
const PathUtils = path_utils.PathUtils;

const FileStream = std.io.FixedBufferStream([]u8);

pub const FileType = enum(u32) {
    empty = 0x1,
    standard = 0x2,
    model = 0x3,
    texture = 0x4,
    _,
};

pub const FileInfo = extern struct {
    header_size: u32,
    file_type: FileType,
    file_size: u32,
};

pub const StandardFileInfo = extern struct {
    _padding0: [8]u8,
    num_of_blocks: u32,
};

pub const TextureFileInfo = StandardFileInfo;

pub const StandardFileBlockInfo = extern struct {
    offset: u32,
    compressed_size: u16,
    uncompressed_size: u16,
};

pub const TextureFileBlockInfo = extern struct {
    compressed_offset: u32,
    compressed_size: u32,
    decompressed_size: u32,
    block_offset: u32,
    block_count: u32,
};

pub const BlockType = enum(u32) {
    compressed = 16000,
    uncompressed = 32000,
    _,
};

pub const BlockHeader = extern struct {
    size: u32,
    _padding0: u32,
    block_type: BlockType,
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
        const reader = self.file.reader();

        // Jump to the specified offset where the virtual file header starts
        try self.file.seekTo(offset);

        // Get the file info
        const file_info = try reader.readStruct(FileInfo);

        // We can allocate the raw bytes up front
        const raw_bytes = try allocator.alloc(u8, file_info.file_size);
        errdefer allocator.free(raw_bytes);
        var stream = std.io.fixedBufferStream(raw_bytes);

        // Determine the type and read it into the buffer
        switch (file_info.file_type) {
            .empty => {},
            .standard => try self.readStandardFile(offset, file_info, &stream),
            .model => {},
            .texture => try self.readTextureFile(offset, file_info, &stream),
            else => return error.InvalidFileExtension,
        }

        return raw_bytes;
    }

    fn readStandardFile(self: *Self, base_offset: u64, file_info: FileInfo, stream: *FileStream) !void {
        const reader = self.file.reader();

        // Read the standard file info
        const standard_file_info = try reader.readStruct(StandardFileInfo);

        // First we need to allocate space for the block infos
        const block_count = standard_file_info.num_of_blocks;
        const blocks = try self.allocator.alloc(StandardFileBlockInfo, block_count);
        defer self.allocator.free(blocks);

        // Read the block info structs
        for (blocks) |*block| {
            block.* = try reader.readStruct(StandardFileBlockInfo);
        }

        // Now we can read the actual blocks
        for (blocks) |*block| {
            const calculated_offset = base_offset + file_info.header_size + block.offset;
            try self.readFileBlock(calculated_offset, stream);
        }
    }

    fn readTextureFile(self: *Self, base_offset: u64, file_info: FileInfo, stream: *FileStream) !void {
        const reader = self.file.reader();

        // Read the texture file info
        const texture_file_info = try reader.readStruct(TextureFileInfo);

        // First we need to allocate space for the block infos
        const block_count = texture_file_info.num_of_blocks;
        const blocks = try self.allocator.alloc(TextureFileBlockInfo, block_count);
        defer self.allocator.free(blocks);

        // Read the block info structs
        for (blocks) |*block| {
            block.* = try reader.readStruct(TextureFileBlockInfo);
        }

        // Read mip data
        const mipSize = blocks[0].compressed_offset;
        if (mipSize != 0) {
            const original_position = try self.file.getPos();

            try self.file.seekTo(base_offset + file_info.header_size);
            const slice = stream.buffer[stream.pos..][0..mipSize];
            const bytes_read = try reader.readAll(slice);
            stream.pos += bytes_read;

            try self.file.seekTo(original_position);
        }

        // Now we can read the actual blocks
        for (blocks) |*block| {
            var running_total: u64 = base_offset + file_info.header_size + block.compressed_offset;
            for (0..block.block_count) |_| {
                // Remember position again
                const original_position = try self.file.getPos();

                // Read the actual block
                try self.readFileBlock(running_total, stream);

                // Go back to the original position
                try self.file.seekTo(original_position);

                // Get the offset to the next block and add it to the running total
                const offset_to_next = try reader.readInt(u16, .little);
                running_total += offset_to_next;
            }
        }
    }

    fn readFileBlock(self: *Self, offset: u64, stream: *FileStream) !void {
        const reader = self.file.reader();

        // We need to seek to the block offset
        try self.file.seekTo(offset);

        // Read the block header
        const block_header = try reader.readStruct(BlockHeader);

        // Check if the block is compressed or uncompressed
        if (block_header.block_type == .uncompressed) {
            // Uncompressed block so we just copy the bytes
            const slice = stream.buffer[stream.pos..][0..block_header.data_size];
            const bytes_read = try reader.readAll(slice);
            stream.pos += bytes_read;
        } else {
            // Compressed block so we need to decompress it
            try std.compress.flate.decompress(reader, stream.writer());
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
