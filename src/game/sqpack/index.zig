const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const SqPackHeader = native_types.SqPackHeader;
const SqPackIndexHeader = native_types.SqPackIndexHeader;
const SqPackIndex1TableEntry = native_types.SqPackIndex1TableEntry;
const SqPackIndex2TableEntry = native_types.SqPackIndex2TableEntry;

const BufferedFileReader = @import("../../core/io/BufferedFileReader.zig");

pub const Index1 = Index(SqPackIndex1TableEntry);
pub const Index2 = Index(SqPackIndex2TableEntry);

pub fn Index(comptime EntryType: type) type {
    return struct {
        const Self = @This();

        const HashType = @FieldType(EntryType, "hash_data");

        allocator: Allocator,
        pack_header: SqPackHeader,
        index_header: SqPackIndexHeader,
        index_table: IndexTable,

        pub fn init(allocator: Allocator, bfr: *BufferedFileReader) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;

            // Read the pack header
            self.pack_header = try bfr.reader().readStruct(SqPackHeader);
            try self.pack_header.validateMagic();
            _ = try bfr.seekTo(self.pack_header.size);

            // Read the index header
            self.index_header = try bfr.reader().readStruct(SqPackIndexHeader);
            _ = try bfr.seekTo(self.index_header.size);

            // Read the index table
            try self.index_table.populate(self.allocator, bfr, &self.index_header);

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.index_table.cleanup(self.allocator);
            self.allocator.destroy(self);
        }

        pub fn lookupFileByHash(self: *Self, hash: HashType) ?LookupResult {
            if (self.index_table.lookupFileByHash(hash)) |entry| {
                return .{
                    .data_file_id = entry.dataFileId(),
                    .data_file_offset = entry.dataFileOffset(),
                };
            }

            return null;
        }

        pub const LookupResult = struct {
            data_file_id: u8,
            data_file_offset: u64,
        };

        pub const IndexTable = struct {
            entries: []EntryType,
            hash_table: std.AutoHashMapUnmanaged(HashType, *EntryType),

            pub fn populate(table: *IndexTable, allocator: Allocator, bfr: *BufferedFileReader, header: *SqPackIndexHeader) !void {
                table.hash_table = .{};

                // Calculate the size of the index table and allocate memory for it
                const index_table_entries = header.index_data_size / @sizeOf(EntryType);
                table.entries = try allocator.alloc(EntryType, index_table_entries);
                errdefer allocator.free(table.entries);

                // Seek to the index data offset
                try bfr.seekTo(header.index_data_offset);

                // Read the index data into the entries array
                const entries_bytes = std.mem.sliceAsBytes(table.entries);
                _ = try bfr.reader().readAll(entries_bytes);

                // Populate the hash table with the entries
                try table.hash_table.ensureTotalCapacity(allocator, @intCast(index_table_entries));
                for (table.entries) |*entry| {
                    const hash = entry.hash();
                    table.hash_table.putAssumeCapacity(hash, entry);
                }
            }

            pub fn cleanup(table: *IndexTable, allocator: Allocator) void {
                allocator.free(table.entries);
                table.hash_table.deinit(allocator);
            }

            pub fn lookupFileByHash(table: *IndexTable, hash: HashType) ?*EntryType {
                return table.hash_table.get(hash);
            }
        };
    };
}
