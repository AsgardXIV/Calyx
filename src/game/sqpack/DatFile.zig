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
        .texture => {},
        .model => {},
        else => return error.UnknownFileType,
    }

    return raw_bytes;
}

fn readStandardFile(dat: *DatFile, base_offset: u64, file_info: FileInfo, write_stream: *WriteStream) !void {
    var sfb = std.heap.stackFallback(4096, dat.allocator);
    const sfa = sfb.get();

    // Read the standard file info
    const standard_file_info = try dat.bsr.reader().readStruct(StandardFileInfo);

    // Allocate space for block infos
    const block_count = standard_file_info.num_of_blocks;
    const blocks = try sfa.alloc(StandardFileBlockInfo, block_count);
    defer sfa.free(blocks);

    // Read the block info structs
    for (blocks) |*block| {
        block.* = try dat.bsr.reader().readStruct(StandardFileBlockInfo);
    }

    // Now we can read the actual blocks
    for (blocks) |*block| {
        const calculated_offset = base_offset + file_info.header_size + block.offset;
        _ = try dat.readFileBlock(calculated_offset, write_stream);
    }
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

    const header = try dat.bsr.reader().readStruct(SqPackHeader);
    try header.validateMagic();
}
