const std = @import("std");

const Platform = @import("../common/platform.zig").Platform;
const FileExtension = @import("file_extension.zig").FileExtension;

const path_utils = @import("path_utils.zig");
const ParsedGamePath = path_utils.ParsedGamePath;
const FileLookupResult = path_utils.FileLookupResult;

const Chunk = @import("chunk.zig").Chunk;

const Allocator = std.mem.Allocator;

pub const SqPackHeader = extern struct {
    magic: [8]u8,
    platform: Platform,
    _padding0: [3]u8,
    size: u32,
    version: u32,
    pack_type: u32,
};

pub const SqPackIndexHeader = extern struct {
    size: u32,
    version: u32,
    index_data_offset: u32,
    index_data_size: u32,
    index_data_hash: [64]u8,
    num_data_files: u32,
    synonym_data_offset: u32,
    synonym_data_size: u32,
    synonym_data_hash: [64]u8,
    empy_data_offset: u32,
    empty_data_size: u32,
    empty_data_hash: [64]u8,
    dir_index_offset: u32,
    dir_index_size: u32,
    dir_index_hash: [64]u8,
    index_type: u32,
    _padding0: [656]u8,
    header_hash: [64]u8,
};

pub const SqPackIndex1TableEntry = extern struct {
    pub const IndexFileExtension = FileExtension.index;
    pub const HashType = u64;

    const Self = @This();

    hash_data: HashType,
    packed_data: u32,
    _padding0: u32,

    pub fn hash(self: *const Self) HashType {
        return self.hash_data;
    }

    pub fn dataFileId(self: *const Self) u8 {
        return @truncate((self.packed_data >> 1) & 0b111);
    }

    pub fn dataFileOffset(self: *const Self) u64 {
        const block_offset = self.packed_data & ~@as(u32, 0xF);
        return @as(u64, block_offset) * 0x08;
    }
};

pub const SqPackIndex2TableEntry = extern struct {
    pub const IndexFileExtension = FileExtension.index2;
    pub const HashType = u32;

    const Self = @This();

    hash_data: HashType,
    packed_data: u32,

    pub fn hash(self: *const Self) HashType {
        return self.hash_data;
    }

    pub fn dataFileId(self: *const Self) u8 {
        return @truncate((self.packed_data >> 1) & 0b111);
    }

    pub fn dataFileOffset(self: *const Self) u64 {
        const block_offset = self.packed_data & ~@as(u32, 0xF);
        return @as(u64, block_offset) * 0x08;
    }
};

pub fn Index(comptime EntryType: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        chunk: *Chunk,
        pack_header: SqPackHeader,
        index_header: SqPackIndexHeader,
        index_table: *IndexTable(EntryType),

        pub fn init(allocator: Allocator, chunk: *Chunk, file: *const std.fs.File) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;
            self.chunk = chunk;

            const reader = file.reader();

            // Read the pack header
            self.pack_header = try reader.readStruct(SqPackHeader);
            _ = try file.seekTo(self.pack_header.size);

            // Read the index header
            self.index_header = try reader.readStruct(SqPackIndexHeader);
            _ = try file.seekTo(self.index_header.size);

            // Read the index table
            self.index_table = try IndexTable(EntryType).init(allocator, self, file);
            errdefer self.index_table.cleanup();

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.index_table.cleanup();
            self.allocator.destroy(self);
        }

        pub fn lookupFile(self: *Self, path: ParsedGamePath) ?FileLookupResult {
            const hash = if (EntryType == SqPackIndex1TableEntry) path.index1_hash else path.index2_hash;

            const index_entry = self.index_table.hash_table.get(hash);
            if (index_entry) |entry| {
                return FileLookupResult{
                    .data_file_id = entry.dataFileId(),
                    .data_file_offset = entry.dataFileOffset(),
                    .repo_id = self.chunk.category.repository.repo_id,
                    .category_id = self.chunk.category.category_id,
                    .chunk_id = self.chunk.chunk_id,
                };
            }

            return null;
        }
    };
}

fn IndexTable(comptime InEntryType: type) type {
    return struct {
        pub const EntryType = InEntryType;
        pub const HashType = EntryType.HashType;

        const Self = @This();

        allocator: Allocator,
        entries: []EntryType,
        hash_table: std.AutoArrayHashMapUnmanaged(EntryType.HashType, *EntryType),

        pub fn init(allocator: Allocator, index: *Index(EntryType), file: *const std.fs.File) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;
            self.hash_table = .{};

            // Calculate the size of the index table
            const entry_count = index.index_header.index_data_size / @sizeOf(EntryType);
            self.entries = try allocator.alloc(EntryType, entry_count);
            errdefer allocator.free(self.entries);

            // Skip to the index data offset
            _ = try file.seekTo(index.index_header.index_data_offset);

            // Read the index table entries
            const reader = file.reader();
            const entries_bytes = std.mem.sliceAsBytes(self.entries);
            _ = try reader.readAll(entries_bytes);

            // Populate the hash maps
            try self.populateHashMaps(allocator);

            return self;
        }

        pub fn cleanup(self: *Self) void {
            self.hash_table.deinit(self.allocator);
            self.allocator.free(self.entries);
            self.allocator.destroy(self);
        }

        fn populateHashMaps(self: *Self, allocator: Allocator) !void {
            try self.hash_table.ensureTotalCapacity(allocator, @intCast(self.entries.len));
            for (self.entries) |*entry| {
                const hash = entry.hash();
                self.hash_table.putAssumeCapacity(hash, entry);
            }
        }
    };
}
