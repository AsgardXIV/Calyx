const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const SqPackHeader = native_types.SqPackHeader;
const SqPackIndexHeader = native_types.SqPackIndexHeader;
const SqPackIndex1TableEntry = native_types.SqPackIndex1TableEntry;
const SqPackIndex2TableEntry = native_types.SqPackIndex2TableEntry;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

pub const Index1 = Index(SqPackIndex1TableEntry);
pub const Index2 = Index(SqPackIndex2TableEntry);

fn Index(comptime EntryType: type) type {
    return struct {
        const Self = @This();

        const HashType = @FieldType(EntryType, "hash_data");

        allocator: Allocator,
        pack_header: SqPackHeader,
        index_header: SqPackIndexHeader,
        index_table: IndexTable(HashType, EntryType),

        pub fn init(allocator: Allocator, bsr: *BufferedStreamReader) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;

            // Read the pack header
            self.pack_header = try bsr.reader().readStruct(SqPackHeader);
            try self.pack_header.validateMagic();
            _ = try bsr.seekTo(self.pack_header.size);

            // Read the index header
            self.index_header = try bsr.reader().readStruct(SqPackIndexHeader);
            _ = try bsr.seekTo(self.index_header.size);

            // Read the index table
            try self.index_table.populate(self.allocator, bsr, &self.index_header);

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

        const LookupResult = struct {
            data_file_id: u8,
            data_file_offset: u64,
        };
    };
}

fn IndexTable(comptime HashType: type, comptime EntryType: type) type {
    return struct {
        const Self = @This();

        entries: []EntryType,
        hash_table: std.AutoArrayHashMapUnmanaged(HashType, *EntryType),

        pub fn populate(self: *Self, allocator: Allocator, bsr: *BufferedStreamReader, header: *SqPackIndexHeader) !void {
            self.hash_table = .{};

            // Calculate the size of the index table and allocate memory for it
            const index_table_entries = header.index_data_size / @sizeOf(EntryType);
            self.entries = try allocator.alloc(EntryType, index_table_entries);
            errdefer allocator.free(self.entries);

            // Seek to the index data offset
            try bsr.seekTo(header.index_data_offset);

            // Read the index data into the entries array
            const entries_bytes = std.mem.sliceAsBytes(self.entries);
            _ = try bsr.reader().readAll(entries_bytes);

            // Populate the hash table with the entries
            try self.hash_table.ensureTotalCapacity(allocator, @intCast(index_table_entries));
            for (self.entries) |*entry| {
                const hash = entry.hash();
                self.hash_table.putAssumeCapacity(hash, entry);
            }
        }

        pub fn cleanup(self: *Self, allocator: Allocator) void {
            allocator.free(self.entries);
            self.hash_table.deinit(allocator);
        }

        pub fn lookupFileByHash(self: *Self, hash: HashType) ?*EntryType {
            return self.hash_table.get(hash);
        }
    };
}
