const std = @import("std");

const CategoryId = @import("category_id.zig").CategoryId;
const RepositoryId = @import("repository_id.zig").RepositoryId;

const string = @import("../../core/string.zig");
const hash = @import("../../core/hash.zig");

const ParsedGamePath = @This();

category_id: CategoryId,
repo_id: RepositoryId,
index1_hash: u64,
index2_hash: u32,

pub fn fromPathString(raw_path: []const u8) !ParsedGamePath {
    // Lowercase
    var buffer: [1024]u8 = undefined;
    @memcpy(buffer[0..raw_path.len], raw_path[0..raw_path.len]);
    string.toLowerCase(buffer[0..raw_path.len]);
    const path: []const u8 = buffer[0..raw_path.len];

    // Index 2 hash is easy
    const index2_hash = hash.crc32(path);

    // Split the path into parts
    var path_parts = std.mem.splitScalar(u8, path, '/');

    // Get the category ID
    const category_name = path_parts.next() orelse return error.MalformedPath;
    const category_id = CategoryId.fromCategoryString(category_name) orelse return error.InvalidCategory;

    // Get the repository ID
    const repo_name = path_parts.next() orelse return error.MalformedPath;
    const repo_id = try RepositoryId.fromRepositoryString(repo_name, true);

    // Split what we need for index1
    const last_path_part = std.mem.lastIndexOf(u8, path, "/") orelse return error.InvalidPath;
    const file_only_str = path[last_path_part + 1 ..];
    const file_only_hash = hash.crc32(file_only_str);
    const directory_str = path[0..last_path_part];
    const directory_hash = hash.crc32(directory_str);

    // Pack index1 hash
    const index1_hash: u64 = (@as(u64, directory_hash) << 32) | file_only_hash;

    return .{
        .category_id = category_id,
        .repo_id = repo_id,
        .index1_hash = index1_hash,
        .index2_hash = index2_hash,
    };
}

test "fromPathString" {
    {
        // Basic path with explicit repo ID
        const expected = ParsedGamePath{
            .category_id = CategoryId.chara,
            .repo_id = RepositoryId.fromIntId(6),
            .index1_hash = 0x2e7e889c54cbce06,
            .index2_hash = 0xbed04397,
        };
        const result = try fromPathString("chara/ex6/beep.dat");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Basic path with implicit repo ID

        const expected = ParsedGamePath{
            .category_id = CategoryId.chara,
            .repo_id = RepositoryId.fromIntId(0),
            .index1_hash = 0x7774313e54cbce06,
            .index2_hash = 0x32ca2200,
        };
        const result = try fromPathString("chara/beep.dat");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Path casing is ignored

        const expected = ParsedGamePath{
            .category_id = CategoryId.chara,
            .repo_id = RepositoryId.fromIntId(0),
            .index1_hash = 0x7774313e54cbce06,
            .index2_hash = 0x32ca2200,
        };
        const result = try fromPathString("cHAra/bEEp.daT");
        try std.testing.expectEqual(expected, result);
    }

    {
        // Invalid path, too short
        const expected = error.MalformedPath;
        const result = fromPathString("chara");
        try std.testing.expectError(expected, result);
    }

    {
        // Invalid category ID
        const expected = error.InvalidCategory;
        const result = fromPathString("beep/ex6/test.dat");
        try std.testing.expectError(expected, result);
    }

    {
        // Blank file name, technically allowed as you may just want the directory hash
        const expected = ParsedGamePath{
            .category_id = CategoryId.chara,
            .repo_id = RepositoryId.fromIntId(6),
            .index1_hash = 0xb811ed45ffffffff,
            .index2_hash = 0xaddf99ab,
        };
        const result = try fromPathString("chara/ex6/folder/");
        try std.testing.expectEqual(expected, result);
    }
}
