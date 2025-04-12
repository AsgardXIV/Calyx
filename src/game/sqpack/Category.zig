const std = @import("std");
const Allocator = std.mem.Allocator;

const CategoryId = @import("category_id.zig").CategoryId;

const RepositoryId = @import("repository_id.zig").RepositoryId;
const Platform = @import("../platform.zig").Platform;
const ParsedGamePath = @import("ParsedGamePath.zig");
const PackFileName = @import("PackFileName.zig");
const Chunk = @import("Chunk.zig");

const Category = @This();

allocator: Allocator,
platform: Platform,
repo_id: RepositoryId,
repo_path: []const u8,
category_id: CategoryId,
chunks: std.ArrayListUnmanaged(*Chunk),

pub fn init(allocator: Allocator, platform: Platform, repo_id: RepositoryId, repo_path: []const u8, category_id: CategoryId) !*Category {
    const category = try allocator.create(Category);
    errdefer allocator.destroy(category);

    const cloned_repo_path = try allocator.dupe(u8, repo_path);
    errdefer allocator.free(cloned_repo_path);

    category.* = .{
        .allocator = allocator,
        .platform = platform,
        .repo_id = repo_id,
        .repo_path = cloned_repo_path,
        .category_id = category_id,
        .chunks = .{},
    };

    try category.setupChunks();

    return category;
}

pub fn deinit(category: *Category) void {
    category.cleanupChunks();
    category.allocator.free(category.repo_path);
    category.allocator.destroy(category);
}

pub fn getFileContents(category: *Category, allocator: Allocator, path: ParsedGamePath) ![]const u8 {
    for (category.chunks.items) |chunk| {
        const lookup = chunk.lookupFileInIndexes(path);
        if (lookup) |resolved| {
            return chunk.getFileContentsAtOffset(allocator, resolved.data_file_id, resolved.data_file_offset);
        }
    }

    return error.FileNotFound;
}

fn setupChunks(category: *Category) !void {
    var sfb = std.heap.stackFallback(2048, category.allocator);
    const sfa = sfb.get();

    errdefer category.cleanupChunks();

    // Discover all valid chunks
    const first_invalid_chunk = for (0..256) |chunk_id| {
        // See if there are indexes for this chunk
        const chunk_exists = ext_loop: for ([_]PackFileName.Extension{ .index, .index2 }) |ext| {
            const file_name = PackFileName.buildSqPackFileName(
                sfa,
                category.category_id,
                category.repo_id,
                @intCast(chunk_id),
                category.platform,
                ext,
                null,
            ) catch continue :ext_loop;
            defer sfa.free(file_name);

            const file_path = std.fs.path.join(sfa, &.{ category.repo_path, file_name }) catch continue :ext_loop;
            defer sfa.free(file_path);

            std.fs.accessAbsolute(file_path, .{}) catch continue :ext_loop;

            break :ext_loop true;
        } else false;

        // No chunk exists, they are sequential so we're done
        if (!chunk_exists) break chunk_id;
    } else 0;

    // Setup the chunks
    try category.chunks.ensureTotalCapacity(category.allocator, first_invalid_chunk);
    for (0..first_invalid_chunk) |chunk_id| {
        // Create the chunk
        const chunk = try Chunk.init(
            category.allocator,
            category.platform,
            category.repo_id,
            category.repo_path,
            category.category_id,
            @intCast(chunk_id),
        );
        errdefer chunk.deinit();

        // Store the chunk
        category.chunks.appendAssumeCapacity(chunk);
    }
}

fn cleanupChunks(category: *Category) void {
    for (category.chunks.items) |chunk| {
        chunk.deinit();
    }
    category.chunks.deinit(category.allocator);
}
