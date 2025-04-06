const std = @import("std");

const Platform = @import("../platform.zig").Platform;

pub const SqPackHeader = extern struct {
    const Self = @This();
    const Magic = "SqPack\x00\x00";

    magic: [8]u8,
    platform: Platform,
    _padding0: [3]u8,
    size: u32,
    version: u32,
    pack_type: u32,

    pub fn validateMagic(self: *const Self) !void {
        if (std.mem.eql(u8, &self.magic, Magic)) {
            return;
        } else {
            return error.InvalidMagic;
        }
    }
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
    const Self = @This();

    hash_data: u64,
    packed_data: u32,
    _padding0: u32,

    pub fn hash(self: *const Self) u64 {
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
    const Self = @This();

    hash_data: u32,
    packed_data: u32,

    pub fn hash(self: *const Self) u32 {
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
