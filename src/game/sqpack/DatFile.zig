const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryId = @import("category_id.zig").CategoryId;
const Platform = @import("../platform.zig").Platform;
const RepositoryId = @import("repository_id.zig").RepositoryId;
const PackFileName = @import("PackFileName.zig");

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const native_types = @import("native_types.zig");
const SqPackHeader = native_types.SqPackHeader;
const FileInfo = native_types.FileInfo;
const StandardFileInfo = native_types.StandardFileInfo;
const StandardFileBlockInfo = native_types.StandardFileBlockInfo;
const BlockHeader = native_types.BlockHeader;
const TextureFileInfo = native_types.TextureFileInfo;
const TextureFileBlockInfo = native_types.TextureFileBlockInfo;
const ModelFileInfo = native_types.ModelFileInfo;

const DatFile = @This();

const WriteStream = std.io.FixedBufferStream([]u8);

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunk_id: u8,
file_id: u8,
bsr: BufferedStreamReader,

pub fn init(allocator: Allocator, platform: Platform, repo_id: RepositoryId, repo_path: []const u8, category_id: CategoryId, chunk_id: u8, file_id: u8) !*DatFile {
    const dat = try allocator.create(DatFile);
    errdefer allocator.destroy(dat);

    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    dat.* = .{
        .allocator = allocator,
        .platform = platform,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .category_id = category_id,
        .chunk_id = chunk_id,
        .file_id = file_id,
        .bsr = undefined,
    };

    try dat.mountDatFile();

    return dat;
}

pub fn deinit(dat: *DatFile) void {
    dat.bsr.close();
    dat.allocator.free(dat.repo_path);
    dat.allocator.destroy(dat);
}

pub fn getFileContentsAtOffset(dat: *DatFile, allocator: Allocator, offset: u64) ![]const u8 {
    return readFile(dat, allocator, offset);
}

fn readFile(dat: *DatFile, allocator: Allocator, offset: u64) ![]const u8 {
    const reader = dat.bsr.reader();

    // Jump to the offset first
    try dat.bsr.seekTo(offset);

    // Read the file info
    const file_info = try reader.readStruct(FileInfo);

    // We can now allocate the file contents
    const raw_bytes = try allocator.alloc(u8, file_info.file_size);
    errdefer allocator.free(raw_bytes);
    var write_stream = std.io.fixedBufferStream(raw_bytes);

    // Determine the file type
    switch (file_info.file_type) {
        .empty => {},
        .standard => try dat.readStandardFile(offset, file_info, &write_stream),
        .texture => try dat.readTextureFile(offset, file_info, &write_stream),
        .model => try dat.readModelFile(offset, file_info, &write_stream),
        else => return error.UnknownFileType,
    }

    return raw_bytes;
}

fn readStandardFile(dat: *DatFile, base_offset: u64, file_info: FileInfo, write_stream: *WriteStream) !void {
    var sfb = std.heap.stackFallback(4096, dat.allocator);
    const sfa = sfb.get();

    // Read the standard file info
    const standard_file_info = try dat.bsr.reader().readStruct(StandardFileInfo);

    // Read the block infos
    const block_count = standard_file_info.num_of_blocks;
    const blocks = try sfa.alloc(StandardFileBlockInfo, block_count);
    defer sfa.free(blocks);
    const block_slice = std.mem.sliceAsBytes(blocks);
    _ = try dat.bsr.reader().readAll(block_slice);

    // Now we can read the actual blocks
    for (blocks) |*block| {
        const calculated_offset = base_offset + file_info.header_size + block.offset;
        _ = try dat.readFileBlock(calculated_offset, write_stream);
    }
}

fn readTextureFile(dat: *DatFile, base_offset: u64, file_info: FileInfo, write_stream: *WriteStream) !void {
    var sfb = std.heap.stackFallback(4096, dat.allocator);
    const sfa = sfb.get();

    // Read the texture file info
    const texture_file_info = try dat.bsr.reader().readStruct(TextureFileInfo);

    // Read the block infos
    const block_count = texture_file_info.num_of_blocks;
    const blocks = try sfa.alloc(TextureFileBlockInfo, block_count);
    defer sfa.free(blocks);
    const block_slice = std.mem.sliceAsBytes(blocks);
    _ = try dat.bsr.reader().readAll(block_slice);

    // Read mip data
    const mip_size = blocks[0].compressed_offset;
    if (mip_size != 0) {
        const original_position = try dat.bsr.getPos();

        try dat.bsr.seekTo(base_offset + file_info.header_size);
        const mip_slice = write_stream.buffer[write_stream.pos..][0..mip_size];
        const mip_bytes_read = try dat.bsr.reader().readAll(mip_slice);
        write_stream.pos += mip_bytes_read;

        try dat.bsr.seekTo(original_position);
    }

    // Now we can read the actual blocks
    for (blocks) |*block| {
        var running_total: u64 = base_offset + file_info.header_size + block.compressed_offset;
        for (0..block.block_count) |_| {
            // Remember position again
            const original_position = try dat.bsr.getPos();

            // Read the actual block
            _ = try dat.readFileBlock(running_total, write_stream);

            // Go back to the original position
            try dat.bsr.seekTo(original_position);

            // Get the offset to the next block and add it to the running total
            const offset_to_next = try dat.bsr.reader().readInt(u16, .little);
            running_total += offset_to_next;
        }
    }
}

fn readModelFile(dat: *DatFile, base_offset: u64, file_info: FileInfo, write_stream: *WriteStream) !void {
    var sfb = std.heap.stackFallback(4096, dat.allocator);
    const sfa = sfb.get();

    // Read the model file info
    const model_file_info = try dat.bsr.reader().readStruct(ModelFileInfo);

    // Calculate total blocks
    const total_blocks = model_file_info.num.calculateTotal();

    // Allocate and assign the block sizes
    const compressed_block_sizes = try sfa.alloc(u16, total_blocks);
    defer sfa.free(compressed_block_sizes);
    const compressed_block_slice = std.mem.sliceAsBytes(compressed_block_sizes);
    _ = try dat.bsr.reader().readAll(compressed_block_slice);

    // Setup some temp data
    var vertex_data_offsets: [ModelFileInfo.LodLevels]u32 = undefined;
    var vertex_data_sizes: [ModelFileInfo.LodLevels]u32 = undefined;

    var edge_data_offsets: [ModelFileInfo.LodLevels]u32 = undefined;
    var edge_data_sizes: [ModelFileInfo.LodLevels]u32 = undefined;

    var index_data_offsets: [ModelFileInfo.LodLevels]u32 = undefined;
    var index_data_sizes: [ModelFileInfo.LodLevels]u32 = undefined;

    // Start writing at 0x44 and we'll fill in the header later
    write_stream.pos = 0x44;

    var current_block: u32 = 0;

    const stack_offset = base_offset + file_info.header_size + model_file_info.offset.stack_size;
    const stack_result = try dat.readModelBlocks(stack_offset, model_file_info.num.stack_size, current_block, compressed_block_sizes, write_stream);
    current_block = stack_result.next_block;
    const stack_size: u32 = @intCast(stack_result.size);

    const runtime_offset = base_offset + file_info.header_size + model_file_info.offset.runtime_size;
    const runtime_result = try dat.readModelBlocks(runtime_offset, model_file_info.num.runtime_size, current_block, compressed_block_sizes, write_stream);
    current_block = runtime_result.next_block;
    const runtime_size: u32 = @intCast(runtime_result.size);

    for (0..ModelFileInfo.LodLevels) |lod| {
        const vertex_offset = base_offset + file_info.header_size + model_file_info.offset.vertex_buffer_size[lod];
        current_block = try dat.processModelData(
            lod,
            vertex_offset,
            model_file_info.num.vertex_buffer_size[lod],
            current_block,
            &vertex_data_offsets,
            &vertex_data_sizes,
            compressed_block_sizes,
            write_stream,
        );

        // TODO: Is this even correct? No models seem to have this data for win32
        const edge_data_offset = base_offset + file_info.header_size + model_file_info.offset.edge_geometry_vertex_buffer_size[lod];
        current_block = try dat.processModelData(
            lod,
            edge_data_offset,
            model_file_info.num.edge_geometry_vertex_buffer_size[lod],
            current_block,
            &edge_data_offsets,
            &edge_data_sizes,
            compressed_block_sizes,
            write_stream,
        );

        const index_offset = base_offset + file_info.header_size + model_file_info.offset.index_buffer_size[lod];
        current_block = try dat.processModelData(
            lod,
            index_offset,
            model_file_info.num.index_buffer_size[lod],
            current_block,
            &index_data_offsets,
            &index_data_sizes,
            compressed_block_sizes,
            write_stream,
        );
    }

    // Write the first 0x44 bytes
    write_stream.pos = 0;
    const writer = write_stream.writer();
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

fn readModelBlocks(dat: *DatFile, offset: u64, size: usize, start_block: u32, compressed_block_sizes: []u16, write_stream: *WriteStream) !struct { size: u64, next_block: u32 } {
    const stack_start = write_stream.pos;
    var current_block = start_block;
    try dat.bsr.seekTo(offset);

    for (0..size) |_| {
        const last_pos = try dat.bsr.getPos();
        _ = try dat.readFileBlock(null, write_stream);
        try dat.bsr.seekTo(last_pos + compressed_block_sizes[current_block]);
        current_block += 1;
    }
    const stack_size = write_stream.pos - stack_start;
    return .{ .size = stack_size, .next_block = current_block };
}

fn processModelData(dat: *DatFile, lod: usize, offset: u64, size: usize, start_block: u32, offsets: *[ModelFileInfo.LodLevels]u32, data_sizes: *[ModelFileInfo.LodLevels]u32, compressed_block_sizes: []u16, write_stream: *WriteStream) !u32 {
    var current_block = start_block;
    offsets[lod] = 0;
    data_sizes[lod] = 0;

    if (size != 0) {
        const current_vertex_offset: u32 = @intCast(write_stream.pos);
        if (lod == 0 or current_vertex_offset != offsets[lod - 1]) {
            offsets[lod] = current_vertex_offset;
        }

        try dat.bsr.seekTo(offset);

        for (0..size) |_| {
            const last_pos = try dat.bsr.getPos();
            const bytes_read = try dat.readFileBlock(null, write_stream);
            data_sizes[lod] += @intCast(bytes_read);

            try dat.bsr.seekTo(last_pos + compressed_block_sizes[current_block]);
            current_block += 1;
        }
    }

    return current_block;
}

fn readFileBlock(dat: *DatFile, offset: ?u64, write_stream: *WriteStream) !u64 {
    // We need to seek to the block offset
    if (offset) |x| {
        try dat.bsr.seekTo(x);
    }

    const reader = dat.bsr.reader();

    // Read the block header
    const block_header = try reader.readStruct(BlockHeader);

    // Check if the block is compressed or uncompressed
    if (block_header.block_type == .uncompressed) {
        // Uncompressed block so we just copy the bytes
        const slice = write_stream.buffer[write_stream.pos..][0..block_header.data_size];
        const bytes_read = try reader.readAll(slice);
        write_stream.pos += bytes_read;
        return bytes_read;
    } else {
        // Compressed block so we need to decompress it
        const initial_pos = write_stream.pos;
        try std.compress.flate.decompress(reader, write_stream.writer());
        return write_stream.pos - initial_pos;
    }
}

fn mountDatFile(dat: *DatFile) !void {
    var sfb = std.heap.stackFallback(2048, dat.allocator);
    const sfa = sfb.get();

    const pack_file_name = PackFileName{
        .platform = dat.platform,
        .repo_id = dat.repo_id,
        .category_id = dat.category_id,
        .chunk_id = dat.chunk_id,
        .file_extension = PackFileName.Extension.dat,
        .file_idx = dat.file_id,
    };

    const pack_file_str = try pack_file_name.toPackFileString(sfa);
    defer sfa.free(pack_file_str);

    const file_path = try std.fs.path.join(sfa, &.{ dat.repo_path, pack_file_str });
    defer sfa.free(file_path);

    dat.bsr = try BufferedStreamReader.initFromPath(file_path);

    if (dat.file_id == 0) {
        const header = try dat.bsr.reader().readStruct(SqPackHeader);
        try header.validateMagic();
    }
}
