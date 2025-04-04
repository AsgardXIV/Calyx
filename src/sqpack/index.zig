const std = @import("std");

const path_utils = @import("path_utils.zig");
const ParsedGamePath = path_utils.ParsedGamePath;
const FileLookupResult = path_utils.FileLookupResult;

const Chunk = @import("chunk.zig").Chunk;

const types = @import("types.zig");

const Allocator = std.mem.Allocator;

pub fn Index(comptime EntryType: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        chunk: *Chunk,
        pack_header: types.SqPackHeader,
        index_header: types.SqPackIndexHeader,
        index_table: *IndexTable(EntryType),

        pub fn init(allocator: Allocator, chunk: *Chunk, file: *const std.fs.File) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;
            self.chunk = chunk;

            const reader = file.reader();

            // Read the pack header
            self.pack_header = try reader.readStruct(types.SqPackHeader);
            try self.pack_header.validateMagic();
            _ = try file.seekTo(self.pack_header.size);

            // Read the index header
            self.index_header = try reader.readStruct(types.SqPackIndexHeader);
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
            const hash = if (EntryType == types.SqPackIndex1TableEntry) path.index1_hash else path.index2_hash;

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
