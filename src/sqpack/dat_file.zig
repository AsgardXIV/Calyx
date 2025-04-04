const std = @import("std");

const Allocator = std.mem.Allocator;

const Chunk = @import("chunk.zig").Chunk;

const path_utils = @import("path_utils.zig");
const PathUtils = path_utils.PathUtils;

const FileStream = std.io.FixedBufferStream([]u8);

const BufferedFileReader = @import("../core/buffered_file_reader.zig").BufferedFileReader;

const types = @import("types.zig");

pub const DatFile = struct {
    const Self = @This();
    const DatFileReader = BufferedFileReader(4096);

    allocator: Allocator,
    chunk: *Chunk,
    file_id: u8,
    file: DatFileReader,
    reader: DatFileReader.Reader,

    pub fn init(allocator: Allocator, chunk: *Chunk, file_id: u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .chunk = chunk,
            .file_id = file_id,
            .file = undefined,
            .reader = undefined,
        };

        try self.mountDatFile();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
        self.allocator.destroy(self);
    }

    pub fn readFile(self: *Self, allocator: Allocator, offset: u64) ![]const u8 {
        // Jump to the specified offset where the file header starts
        try self.file.seekTo(offset);

        // Get the file info
        const file_info = try self.reader.readStruct(types.FileInfo);

        // We can allocate the raw bytes up front
        const raw_bytes = try allocator.alloc(u8, file_info.file_size);
        errdefer allocator.free(raw_bytes);
        var stream = std.io.fixedBufferStream(raw_bytes);

        // Determine the type and read it into the buffer
        switch (file_info.file_type) {
            .empty => {},
            .standard => try self.readStandardFile(offset, file_info, &stream),
            .model => try self.readModelFile(offset, file_info, &stream),
            .texture => try self.readTextureFile(offset, file_info, &stream),
            else => return error.InvalidFileExtension,
        }

        return raw_bytes;
    }

    fn readStandardFile(self: *Self, base_offset: u64, file_info: types.FileInfo, stream: *FileStream) !void {
        var sfb = std.heap.stackFallback(4096, self.allocator);
        const sfa = sfb.get();

        // Read the standard file info
        const standard_file_info = try self.reader.readStruct(types.StandardFileInfo);

        // First we need to allocate space for the block infos
        const block_count = standard_file_info.num_of_blocks;
        const blocks = try sfa.alloc(types.StandardFileBlockInfo, block_count);
        defer sfa.free(blocks);

        // Read the block info structs
        for (blocks) |*block| {
            block.* = try self.reader.readStruct(types.StandardFileBlockInfo);
        }

        // Now we can read the actual blocks
        for (blocks) |*block| {
            const calculated_offset = base_offset + file_info.header_size + block.offset;
            _ = try self.readFileBlock(calculated_offset, stream);
        }
    }

    fn readTextureFile(self: *Self, base_offset: u64, file_info: types.FileInfo, stream: *FileStream) !void {
        var sfb = std.heap.stackFallback(4096, self.allocator);
        const sfa = sfb.get();

        // Read the texture file info
        const texture_file_info = try self.reader.readStruct(types.TextureFileInfo);

        // First we need to allocate space for the block infos
        const block_count = texture_file_info.num_of_blocks;
        const blocks = try sfa.alloc(types.TextureFileBlockInfo, block_count);
        defer sfa.free(blocks);

        // Read the block info structs
        for (blocks) |*block| {
            block.* = try self.reader.readStruct(types.TextureFileBlockInfo);
        }

        // Read mip data
        const mipSize = blocks[0].compressed_offset;
        if (mipSize != 0) {
            const original_position = self.file.getPos();

            try self.file.seekTo(base_offset + file_info.header_size);
            const slice = stream.buffer[stream.pos..][0..mipSize];
            const bytes_read = try self.reader.readAll(slice);
            stream.pos += bytes_read;

            try self.file.seekTo(original_position);
        }

        // Now we can read the actual blocks
        for (blocks) |*block| {
            var running_total: u64 = base_offset + file_info.header_size + block.compressed_offset;
            for (0..block.block_count) |_| {
                // Remember position again
                const original_position = self.file.getPos();

                // Read the actual block
                _ = try self.readFileBlock(running_total, stream);

                // Go back to the original position
                try self.file.seekTo(original_position);

                // Get the offset to the next block and add it to the running total
                const offset_to_next = try self.reader.readInt(u16, .little);
                running_total += offset_to_next;
            }
        }
    }

    fn readModelFile(self: *Self, base_offset: u64, file_info: types.FileInfo, stream: *FileStream) !void {
        var sfb = std.heap.stackFallback(4096, self.allocator);
        const sfa = sfb.get();

        // Read the model file info
        const model_file_info = try self.reader.readStruct(types.ModelFileInfo);

        // Calculate total blocks
        const total_blocks = model_file_info.num.calculateTotal();

        // Allocate and assign the block sizes
        const compressed_block_sizes = try sfa.alloc(u16, total_blocks);
        defer sfa.free(compressed_block_sizes);
        for (compressed_block_sizes) |*block| {
            block.* = try self.reader.readInt(u16, .little);
        }

        var vertex_data_offsets: [types.ModelFileInfo.lod_levels]u32 = undefined;
        var vertex_data_sizes: [types.ModelFileInfo.lod_levels]u32 = undefined;

        var edge_data_offsets: [types.ModelFileInfo.lod_levels]u32 = undefined;
        var edge_data_sizes: [types.ModelFileInfo.lod_levels]u32 = undefined;

        var index_data_offsets: [types.ModelFileInfo.lod_levels]u32 = undefined;
        var index_data_sizes: [types.ModelFileInfo.lod_levels]u32 = undefined;

        // Start writing at 0x44 apparently
        stream.pos = 0x44;

        var current_block: u32 = 0;

        const stack_offset = base_offset + file_info.header_size + model_file_info.offset.stack_size;
        const stack_result = try self.readModelBlocks(stack_offset, model_file_info.num.stack_size, current_block, compressed_block_sizes, stream);
        current_block = stack_result.next_block;
        const stack_size: u32 = @intCast(stack_result.size);

        const runtime_offset = base_offset + file_info.header_size + model_file_info.offset.runtime_size;
        const runtime_result = try self.readModelBlocks(runtime_offset, model_file_info.num.runtime_size, current_block, compressed_block_sizes, stream);
        current_block = runtime_result.next_block;
        const runtime_size: u32 = @intCast(runtime_result.size);

        for (0..types.ModelFileInfo.lod_levels) |lod| {
            const vertex_offset = base_offset + file_info.header_size + model_file_info.offset.vertex_buffer_size[lod];
            current_block = try self.processModelData(
                lod,
                vertex_offset,
                model_file_info.num.vertex_buffer_size[lod],
                current_block,
                &vertex_data_offsets,
                &vertex_data_sizes,
                compressed_block_sizes,
                stream,
            );

            const edge_data_offset = base_offset + file_info.header_size + model_file_info.offset.edge_geometry_vertex_buffer_size[lod];
            current_block = try self.processModelData(
                lod,
                edge_data_offset,
                model_file_info.num.edge_geometry_vertex_buffer_size[lod],
                current_block,
                &edge_data_offsets,
                &edge_data_sizes,
                compressed_block_sizes,
                stream,
            );

            const index_offset = base_offset + file_info.header_size + model_file_info.offset.index_buffer_size[lod];
            current_block = try self.processModelData(
                lod,
                index_offset,
                model_file_info.num.index_buffer_size[lod],
                current_block,
                &index_data_offsets,
                &index_data_sizes,
                compressed_block_sizes,
                stream,
            );
        }

        stream.pos = 0;
        const writer = stream.writer();
        try writer.writeInt(u32, model_file_info.version, .little);
        try writer.writeInt(u32, stack_size, .little);
        try writer.writeInt(u32, runtime_size, .little);
        try writer.writeInt(u16, model_file_info.vertex_declaration_num, .little);
        try writer.writeInt(u16, model_file_info.material_num, .little);
        for (vertex_data_offsets) |offset| {
            try writer.writeInt(u32, offset, .little);
        }
        for (index_data_offsets) |offset| {
            try writer.writeInt(u32, offset, .little);
        }
        for (vertex_data_sizes) |size| {
            try writer.writeInt(u32, size, .little);
        }
        for (index_data_sizes) |size| {
            try writer.writeInt(u32, size, .little);
        }
        try writer.writeInt(u8, model_file_info.num_lods, .little);
        try writer.writeInt(u8, if (model_file_info.index_buffer_streaming_enabled) 1 else 0, .little);
        try writer.writeInt(u8, if (model_file_info.edge_geometry_enabled) 1 else 0, .little);
        try writer.writeInt(u8, 0, .little);
    }

    fn readModelBlocks(self: *Self, offset: u64, size: usize, start_block: u32, compressed_block_sizes: []u16, stream: *FileStream) !struct { size: u64, next_block: u32 } {
        const stack_start = stream.pos;
        var current_block = start_block;
        try self.file.seekTo(offset);

        for (0..size) |_| {
            const last_pos = self.file.getPos();
            _ = try self.readFileBlock(null, stream);
            try self.file.seekTo(last_pos + compressed_block_sizes[current_block]);
            current_block += 1;
        }
        const stack_size = stream.pos - stack_start;
        return .{ .size = stack_size, .next_block = current_block };
    }

    fn processModelData(self: *Self, lod: usize, offset: u64, size: usize, start_block: u32, offsets: *[types.ModelFileInfo.lod_levels]u32, data_sizes: *[types.ModelFileInfo.lod_levels]u32, compressed_block_sizes: []u16, stream: *FileStream) !u32 {
        var current_block = start_block;
        offsets[lod] = 0;
        data_sizes[lod] = 0;

        if (size != 0) {
            const current_vertex_offset: u32 = @intCast(stream.pos);
            if (lod == 0 or current_vertex_offset != offsets[lod - 1]) {
                offsets[lod] = current_vertex_offset;
            }

            try self.file.seekTo(offset);

            for (0..size) |_| {
                const last_pos = self.file.getPos();
                const bytes_read = try self.readFileBlock(null, stream);
                data_sizes[lod] += @intCast(bytes_read);

                try self.file.seekTo(last_pos + compressed_block_sizes[current_block]);
                current_block += 1;
            }
        }

        return current_block;
    }

    fn readFileBlock(self: *Self, offset: ?u64, stream: *FileStream) !u64 {
        // We need to seek to the block offset
        if (offset) |x| {
            try self.file.seekTo(x);
        }

        // Read the block header
        const block_header = try self.reader.readStruct(types.BlockHeader);

        // Check if the block is compressed or uncompressed
        if (block_header.block_type == .uncompressed) {
            // Uncompressed block so we just copy the bytes
            const slice = stream.buffer[stream.pos..][0..block_header.data_size];
            const bytes_read = try self.reader.readAll(slice);
            stream.pos += bytes_read;
            return bytes_read;
        } else {
            // Compressed block so we need to decompress it
            const initial_pos = stream.pos;
            try std.compress.flate.decompress(self.reader, stream.writer());
            return stream.pos - initial_pos;
        }
    }

    fn mountDatFile(self: *Self) !void {
        var sfb = std.heap.stackFallback(2048, self.allocator);
        const sfa = sfb.get();

        const file_name = try PathUtils.buildSqPackFileNameTyped(sfa, .{
            .platform = self.chunk.category.repository.pack.game_data.platform,
            .repo_id = self.chunk.category.repository.repo_id,
            .category_id = self.chunk.category.category_id,
            .chunk_id = self.chunk.chunk_id,
            .file_type = .dat,
            .file_idx = self.file_id,
        });
        defer sfa.free(file_name);

        const file_path = try std.fs.path.join(sfa, &.{ self.chunk.category.repository.repo_path, file_name });
        defer sfa.free(file_path);

        self.file = try DatFileReader.init(file_path);
        self.reader = self.file.reader();

        const header = try self.file.reader().readStruct(types.SqPackHeader);
        try header.validateMagic();
    }
};
