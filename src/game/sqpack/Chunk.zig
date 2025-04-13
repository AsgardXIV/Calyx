const std = @import("std");
const Allocator = std.mem.Allocator;

const Category = @import("Category.zig");

const Platform = @import("../platform.zig").Platform;
const RepositoryId = @import("repository_id.zig").RepositoryId;
const CategoryId = @import("category_id.zig").CategoryId;
const ResolvedGameFile = @import("ResolvedGameFile.zig");
const PackFileName = @import("PackFileName.zig");
const ParsedGamePath = @import("ParsedGamePath.zig");
const index = @import("index.zig");
const Index1 = index.Index1;
const Index2 = index.Index2;
const DataFile = @import("DataFile.zig");

const BufferedFileReader = @import("../../core/io/BufferedFileReader.zig");

const Chunk = @This();

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunk_id: u8,
index1: ?*Index1 = null,
index2: ?*Index2 = null,
data_files: []?*DataFile,

pub fn init(
    allocator: Allocator,
    platform: Platform,
    repo_id: RepositoryId,
    repo_path: []const u8,
    category_id: CategoryId,
    chunk_id: u8,
) !*Chunk {
    const chunk = try allocator.create(Chunk);
    errdefer allocator.destroy(chunk);

    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    chunk.* = .{
        .allocator = allocator,
        .platform = platform,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .category_id = category_id,
        .chunk_id = chunk_id,
        .index1 = null,
        .index2 = null,
        .data_files = &[_]?*DataFile{},
    };

    try chunk.setupIndexes();
    errdefer chunk.cleanupIndexes();

    try chunk.setupDataFiles();
    errdefer chunk.cleanupDataFiles();

    return chunk;
}

pub fn deinit(chunk: *Chunk) void {
    chunk.cleanupDataFiles();
    chunk.cleanupIndexes();
    chunk.allocator.free(chunk.repo_path);
    chunk.allocator.destroy(chunk);
}

pub fn getFileContentsAtOffset(chunk: *Chunk, allocator: Allocator, dat_id: u8, offset: u64) ![]const u8 {
    const dat_file = try getDataFileById(chunk, dat_id);
    return try dat_file.getFileContentsAtOffset(allocator, offset);
}

pub fn lookupFileInIndexes(chunk: *Chunk, path: ParsedGamePath) ?ResolvedGameFile {
    // We check both indexes for the file
    // The first one that returns a result is the one we use
    const lookup_result = blk: {
        if (chunk.index1) |idx| {
            if (idx.lookupFileByHash(path.index1_hash)) |result| {
                break :blk result;
            }
        }

        if (chunk.index2) |idx| {
            if (idx.lookupFileByHash(path.index2_hash)) |result| {
                break :blk result;
            }
        }

        break :blk null;
    };

    // If we found a result, we need to build the resolved game file
    if (lookup_result) |result| {
        return .{
            .data_file_id = result.data_file_id,
            .data_file_offset = result.data_file_offset,
            .repo_id = chunk.repo_id,
            .category_id = chunk.category_id,
            .chunk_id = chunk.chunk_id,
        };
    }

    // If we didn't find a result, we return null
    return null;
}

fn getDataFileById(chunk: *Chunk, data_file_id: u8) !*DataFile {
    if (data_file_id >= chunk.data_files.len) {
        return error.InvalidDataFileId;
    }

    if (chunk.data_files[data_file_id] == null) {
        const data_file = try DataFile.init(
            chunk.allocator,
            chunk.platform,
            chunk.repo_id,
            chunk.repo_path,
            chunk.category_id,
            chunk.chunk_id,
            data_file_id,
        );

        chunk.data_files[data_file_id] = data_file;

        return data_file;
    }

    return chunk.data_files[data_file_id].?;
}

fn setupIndexes(chunk: *Chunk) !void {
    chunk.index1 = try chunk.setupIndex(Index1, PackFileName.Extension.index);
    chunk.index2 = try chunk.setupIndex(Index2, PackFileName.Extension.index2);
}

fn setupIndex(chunk: *Chunk, comptime IndexType: type, extension: PackFileName.Extension) !*IndexType {
    var sfb = std.heap.stackFallback(2048, chunk.allocator);
    const sfa = sfb.get();

    const index_filename = try PackFileName.buildSqPackFileName(
        sfa,
        chunk.category_id,
        chunk.repo_id,
        chunk.chunk_id,
        chunk.platform,
        extension,
        null,
    );
    defer sfa.free(index_filename);

    const index_path = try std.fs.path.join(sfa, &.{ chunk.repo_path, index_filename });
    defer sfa.free(index_path);

    var buffer = BufferedFileReader.initFromPath(index_path) catch null;
    defer if (buffer) |*buf| buf.close();

    if (buffer) |*buf| {
        return try IndexType.init(chunk.allocator, buf);
    }

    return error.FailedToOpenIndexFile;
}

fn cleanupIndexes(chunk: *Chunk) void {
    if (chunk.index1) |idx| idx.deinit();
    if (chunk.index2) |idx| idx.deinit();
}

fn setupDataFiles(chunk: *Chunk) !void {
    const data_file_count = blk: {
        if (chunk.index1) |idx| {
            break :blk idx.index_header.num_data_files;
        }

        if (chunk.index2) |idx| {
            break :blk idx.index_header.num_data_files;
        }

        break :blk null;
    } orelse return error.NoDataFiles;

    chunk.data_files = try chunk.allocator.alloc(?*DataFile, data_file_count);
    @memset(chunk.data_files, null);
    errdefer chunk.allocator.free(chunk.data_files);
}

fn cleanupDataFiles(chunk: *Chunk) void {
    for (chunk.data_files) |opt_datafile| {
        if (opt_datafile) |data_file| {
            data_file.deinit();
        }
    }
    chunk.allocator.free(chunk.data_files);
}
