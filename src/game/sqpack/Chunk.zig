const std = @import("std");
const Allocator = std.mem.Allocator;

const Category = @import("Category.zig");

const Platform = @import("../platform.zig").Platform;
const RepositoryId = @import("repository_id.zig").RepositoryId;
const CategoryId = @import("category_id.zig").CategoryId;
const ResolvedGameFile = @import("ResolvedGameFile.zig");
const PackFileName = @import("PackFileName.zig");
const DatFile = @import("DatFile.zig");
const ParsedGamePath = @import("ParsedGamePath.zig");

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const index = @import("index.zig");
const Index1 = index.Index1;
const Index2 = index.Index2;

const Chunk = @This();

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunk_id: u8,
index1: ?*Index1 = null,
index2: ?*Index2 = null,
dat_files: std.AutoHashMapUnmanaged(u8, *DatFile),

pub fn init(allocator: Allocator, platform: Platform, repo_id: RepositoryId, repo_path: []const u8, category_id: CategoryId, chunk_id: u8) !*Chunk {
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
        .dat_files = .{},
    };

    // Setup the indexes
    try chunk.setupIndexes();

    return chunk;
}

pub fn deinit(chunk: *Chunk) void {
    chunk.cleanupDatFiles();
    chunk.cleanupIndexes();
    chunk.allocator.free(chunk.repo_path);
    chunk.allocator.destroy(chunk);
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

pub fn getFileContentsAtOffset(chunk: *Chunk, allocator: Allocator, dat_id: u8, offset: u64) ![]const u8 {
    const dat_file = try getOrCreateDatFile(chunk, dat_id);
    return try dat_file.getFileContentsAtOffset(allocator, offset);
}

fn getOrCreateDatFile(chunk: *Chunk, file_id: u8) !*DatFile {
    // Check if we already have the dat file
    const dat_file = chunk.dat_files.get(file_id);
    if (dat_file) |dat| {
        return dat;
    }

    // If we don't have it, we need to create it
    const new_dat_file = try DatFile.init(
        chunk.allocator,
        chunk.platform,
        chunk.repo_id,
        chunk.repo_path,
        chunk.category_id,
        chunk.chunk_id,
        file_id,
    );
    errdefer new_dat_file.deinit();

    // Store the dat file in the map
    try chunk.dat_files.put(chunk.allocator, file_id, new_dat_file);

    return new_dat_file;
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

    var buffer = BufferedStreamReader.initFromPath(index_path) catch null;
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

fn cleanupDatFiles(chunk: *Chunk) void {
    var it = chunk.dat_files.valueIterator();
    while (it.next()) |dat_file| {
        dat_file.*.deinit();
    }
    chunk.dat_files.deinit(chunk.allocator);
    chunk.dat_files = .{};
}
