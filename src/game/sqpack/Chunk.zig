const std = @import("std");
const Allocator = std.mem.Allocator;

const Category = @import("Category.zig");

const Platform = @import("../platform.zig").Platform;
const RepositoryId = @import("repository_id.zig").RepositoryId;
const CategoryId = @import("category_id.zig").CategoryId;

const PackFileName = @import("PackFileName.zig");

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
    };

    // Setup the indexes
    try chunk.setupIndexes();

    return chunk;
}

pub fn deinit(chunk: *Chunk) void {
    chunk.cleanupIndexes();
    chunk.allocator.free(chunk.repo_path);
    chunk.allocator.destroy(chunk);
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
