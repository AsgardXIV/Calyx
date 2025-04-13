const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryId = @import("category_id.zig").CategoryId;
const Platform = @import("../platform.zig").Platform;
const RepositoryId = @import("repository_id.zig").RepositoryId;
const PackFileName = @import("PackFileName.zig");

const native_types = @import("native_types.zig");
const SqPackHeader = native_types.SqPackHeader;
const FileInfo = native_types.FileInfo;
const StandardFileInfo = native_types.StandardFileInfo;
const StandardFileBlockInfo = native_types.StandardFileBlockInfo;
const BlockHeader = native_types.BlockHeader;
const TextureFileInfo = native_types.TextureFileInfo;
const TextureFileBlockInfo = native_types.TextureFileBlockInfo;
const ModelFileInfo = native_types.ModelFileInfo;

const BufferedFileReader = @import("../../core/io/BufferedFileReader.zig");

const native_endian = @import("builtin").cpu.arch.endian();

const WriteStream = std.io.FixedBufferStream([]u8);

const DataFile = @This();

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunk_id: u8,
file_id: u8,
bfr: BufferedFileReader,

pub fn init(
    allocator: Allocator,
    platform: Platform,
    repo_id: RepositoryId,
    repo_path: []const u8,
    category_id: CategoryId,
    chunk_id: u8,
    file_id: u8,
) !*DataFile {
    const data_file = try allocator.create(DataFile);
    errdefer allocator.destroy(data_file);

    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    data_file.* = .{
        .allocator = allocator,
        .platform = platform,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .category_id = category_id,
        .chunk_id = chunk_id,
        .file_id = file_id,
        .bfr = undefined,
    };

    try data_file.mountDataFile();

    return data_file;
}

pub fn deinit(data_file: *DataFile) void {
    data_file.bfr.close();
    data_file.allocator.free(data_file.repo_path);
    data_file.allocator.destroy(data_file);
}

pub fn getFileContentsAtOffset(data_file: *DataFile, allocator: Allocator, offset: u64) ![]const u8 {
    return data_file.readFile(allocator, offset);
}

fn readFile(data_file: *DataFile, allocator: Allocator, offset: u64) ![]const u8 {
    const reader = data_file.bfr.reader();

    // Jump to the offset first
    try data_file.bfr.seekTo(offset);

    // Read the file info
    const file_info = try reader.readStruct(FileInfo);

    // We can now allocate the file contents
    const raw_bytes = try allocator.alloc(u8, file_info.file_size);
    errdefer allocator.free(raw_bytes);
    var write_stream = std.io.fixedBufferStream(raw_bytes);

    // Determine the file type
    switch (file_info.file_type) {
        .empty => {},
        .standard => try data_file.readStandardFile(offset, file_info, &write_stream),
        .texture => try data_file.readTextureFile(offset, file_info, &write_stream),
        .model => try data_file.readModelFile(offset, file_info, &write_stream),
        else => return error.UnknownFileType,
    }

    return raw_bytes;
}

fn readStandardFile(data_file: *DataFile, base_offset: u64, file_info: FileInfo, write_stream: *WriteStream) !void {
    var sfb = std.heap.stackFallback(4096, data_file.allocator);
    const sfa = sfb.get();

    // Read the standard file info
    const standard_file_info = try data_file.bfr.reader().readStruct(StandardFileInfo);

    // Read the block infos
    const block_count = standard_file_info.num_of_blocks;
    const blocks = try sfa.alloc(StandardFileBlockInfo, block_count);
    defer sfa.free(blocks);
    const block_slice = std.mem.sliceAsBytes(blocks);
    _ = try data_file.bfr.reader().readAll(block_slice);

    // Now we can read the actual blocks
    for (blocks) |*block| {
        const calculated_offset = base_offset + file_info.header_size + block.offset;
        _ = try data_file.readFileBlock(calculated_offset, write_stream);
    }
}

fn readTextureFile(data_file: *DataFile, base_offset: u64, file_info: FileInfo, write_stream: *WriteStream) !void {
    var sfb = std.heap.stackFallback(4096, data_file.allocator);
    const sfa = sfb.get();

    // Read the texture file info
    const texture_file_info = try data_file.bfr.reader().readStruct(TextureFileInfo);

    // Read the block infos
    const block_count = texture_file_info.num_of_blocks;
    const blocks = try sfa.alloc(TextureFileBlockInfo, block_count);
    defer sfa.free(blocks);
    const block_slice = std.mem.sliceAsBytes(blocks);
    _ = try data_file.bfr.reader().readAll(block_slice);

    // Read mip data
    const mip_size = blocks[0].compressed_offset;
    if (mip_size != 0) {
        const original_position = try data_file.bfr.getPos();

        try data_file.bfr.seekTo(base_offset + file_info.header_size);
        const mip_slice = write_stream.buffer[write_stream.pos..][0..mip_size];
        const mip_bytes_read = try data_file.bfr.reader().readAll(mip_slice);
        write_stream.pos += mip_bytes_read;

        try data_file.bfr.seekTo(original_position);
    }

    // Sum the block counts
    var sub_block_count: usize = 0;
    for (blocks) |*block| {
        sub_block_count += block.block_count;
    }

    // Read the sub block offsets
    const sub_block_offsets = try sfa.alloc(u16, sub_block_count);
    defer sfa.free(sub_block_offsets);
    const sub_block_offsets_slice = std.mem.sliceAsBytes(sub_block_offsets);
    _ = try data_file.bfr.reader().readAll(sub_block_offsets_slice);

    // Now we can read the actual blocks
    var sub_block_index: usize = 0;
    for (blocks) |*block| {
        const root_offset = base_offset + file_info.header_size + block.compressed_offset;
        var next_offset = root_offset;
        for (0..block.block_count) |_| {
            // Read the actual block
            _ = try data_file.readFileBlock(next_offset, write_stream);

            // Increment the sub block index
            next_offset += sub_block_offsets[sub_block_index];
            sub_block_index += 1;
        }
    }
}

fn readModelFile(data_file: *DataFile, base_offset: u64, file_info: FileInfo, write_stream: *WriteStream) !void {
    var sfb = std.heap.stackFallback(4096, data_file.allocator);
    const sfa = sfb.get();

    // Read the model file info
    const model_file_info = try data_file.bfr.reader().readStruct(ModelFileInfo);

    // Calculate total blocks
    const total_blocks = model_file_info.num.calculateTotal();

    // Allocate and assign the block sizes
    const compressed_block_sizes = try sfa.alloc(u16, total_blocks);
    defer sfa.free(compressed_block_sizes);
    const compressed_block_slice = std.mem.sliceAsBytes(compressed_block_sizes);
    _ = try data_file.bfr.reader().readAll(compressed_block_slice);

    // Setup some temp data
    var vertex_data_offsets: [ModelFileInfo.lod_levels]u32 = undefined;
    var vertex_data_sizes: [ModelFileInfo.lod_levels]u32 = undefined;

    var edge_data_offsets: [ModelFileInfo.lod_levels]u32 = undefined;
    var edge_data_sizes: [ModelFileInfo.lod_levels]u32 = undefined;

    var index_data_offsets: [ModelFileInfo.lod_levels]u32 = undefined;
    var index_data_sizes: [ModelFileInfo.lod_levels]u32 = undefined;

    // Start writing at 0x44 and we'll fill in the header later
    write_stream.pos = 0x44;

    var current_block: u32 = 0;

    const stack_offset = base_offset + file_info.header_size + model_file_info.offset.stack_size;
    const stack_result = try data_file.readModelBlocks(stack_offset, model_file_info.num.stack_size, current_block, compressed_block_sizes, write_stream);
    current_block = stack_result.next_block;
    const stack_size: u32 = @intCast(stack_result.size);

    const runtime_offset = base_offset + file_info.header_size + model_file_info.offset.runtime_size;
    const runtime_result = try data_file.readModelBlocks(runtime_offset, model_file_info.num.runtime_size, current_block, compressed_block_sizes, write_stream);
    current_block = runtime_result.next_block;
    const runtime_size: u32 = @intCast(runtime_result.size);

    for (0..ModelFileInfo.lod_levels) |lod| {
        const vertex_offset = base_offset + file_info.header_size + model_file_info.offset.vertex_buffer_size[lod];
        current_block = try data_file.processModelData(
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
        current_block = try data_file.processModelData(
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
        current_block = try data_file.processModelData(
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
    try writer.writeInt(u32, model_file_info.version, native_endian);
    try writer.writeInt(u32, stack_size, native_endian);
    try writer.writeInt(u32, runtime_size, native_endian);
    try writer.writeInt(u16, model_file_info.vertex_declaration_num, native_endian);
    try writer.writeInt(u16, model_file_info.material_num, native_endian);
    for (vertex_data_offsets) |offset| {
        try writer.writeInt(u32, offset, native_endian);
    }
    for (index_data_offsets) |offset| {
        try writer.writeInt(u32, offset, native_endian);
    }
    for (vertex_data_sizes) |size| {
        try writer.writeInt(u32, size, native_endian);
    }
    for (index_data_sizes) |size| {
        try writer.writeInt(u32, size, native_endian);
    }
    try writer.writeInt(u8, model_file_info.num_lods, native_endian);
    try writer.writeInt(u8, if (model_file_info.index_buffer_streaming_enabled) 1 else 0, native_endian);
    try writer.writeInt(u8, if (model_file_info.edge_geometry_enabled) 1 else 0, native_endian);
    try writer.writeInt(u8, 0, native_endian);
}

fn readModelBlocks(data_file: *DataFile, offset: u64, size: usize, start_block: u32, compressed_block_sizes: []u16, write_stream: *WriteStream) !struct { size: u64, next_block: u32 } {
    const stack_start = write_stream.pos;
    var current_block = start_block;
    try data_file.bfr.seekTo(offset);

    for (0..size) |_| {
        const last_pos = try data_file.bfr.getPos();
        _ = try data_file.readFileBlock(null, write_stream);
        try data_file.bfr.seekTo(last_pos + compressed_block_sizes[current_block]);
        current_block += 1;
    }
    const stack_size = write_stream.pos - stack_start;
    return .{ .size = stack_size, .next_block = current_block };
}

fn processModelData(data_file: *DataFile, lod: usize, offset: u64, size: usize, start_block: u32, offsets: *[ModelFileInfo.lod_levels]u32, data_sizes: *[ModelFileInfo.lod_levels]u32, compressed_block_sizes: []u16, write_stream: *WriteStream) !u32 {
    var current_block = start_block;
    offsets[lod] = 0;
    data_sizes[lod] = 0;

    if (size != 0) {
        const current_vertex_offset: u32 = @intCast(write_stream.pos);
        if (lod == 0 or current_vertex_offset != offsets[lod - 1]) {
            offsets[lod] = current_vertex_offset;
        }

        try data_file.bfr.seekTo(offset);

        for (0..size) |_| {
            const last_pos = try data_file.bfr.getPos();
            const bytes_read = try data_file.readFileBlock(null, write_stream);
            data_sizes[lod] += @intCast(bytes_read);

            try data_file.bfr.seekTo(last_pos + compressed_block_sizes[current_block]);
            current_block += 1;
        }
    }

    return current_block;
}

fn readFileBlock(data_file: *DataFile, offset: ?u64, write_stream: *WriteStream) !u64 {
    // We need to seek to the block offset
    if (offset) |x| {
        try data_file.bfr.seekTo(x);
    }

    const reader = data_file.bfr.reader();

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

fn mountDataFile(data_file: *DataFile) !void {
    var sfb = std.heap.stackFallback(2048, data_file.allocator);
    const sfa = sfb.get();

    const pack_file_name = PackFileName{
        .platform = data_file.platform,
        .repo_id = data_file.repo_id,
        .category_id = data_file.category_id,
        .chunk_id = data_file.chunk_id,
        .file_extension = PackFileName.Extension.dat,
        .file_idx = data_file.file_id,
    };

    const pack_file_str = try pack_file_name.toPackFileString(sfa);
    defer sfa.free(pack_file_str);

    const file_path = try std.fs.path.join(sfa, &.{ data_file.repo_path, pack_file_str });
    defer sfa.free(file_path);

    data_file.bfr = try BufferedFileReader.initFromPath(file_path);

    if (data_file.file_id == 0) {
        const header = try data_file.bfr.reader().readStruct(SqPackHeader);
        try header.validateMagic();
    }
}
