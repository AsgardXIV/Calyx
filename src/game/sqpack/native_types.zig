const std = @import("std");

const Platform = @import("../platform.zig").Platform;

pub const SqPackHeader = extern struct {
    const Self = @This();
    const Magic = "SqPack\x00\x00";

    magic: [8]u8 align(1),
    platform: Platform align(1),
    _padding0: [3]u8 align(1),
    size: u32 align(1),
    version: u32 align(1),
    pack_type: u32 align(1),

    pub fn validateMagic(self: *const Self) !void {
        if (std.mem.eql(u8, &self.magic, Magic)) {
            return;
        } else {
            return error.InvalidMagic;
        }
    }
};

pub const SqPackIndexHeader = extern struct {
    size: u32 align(1),
    version: u32 align(1),
    index_data_offset: u32 align(1),
    index_data_size: u32 align(1),
    index_data_hash: [64]u8 align(1),
    num_data_files: u32 align(1),
    synonym_data_offset: u32 align(1),
    synonym_data_size: u32 align(1),
    synonym_data_hash: [64]u8 align(1),
    empy_data_offset: u32 align(1),
    empty_data_size: u32 align(1),
    empty_data_hash: [64]u8 align(1),
    dir_index_offset: u32 align(1),
    dir_index_size: u32 align(1),
    dir_index_hash: [64]u8 align(1),
    index_type: u32 align(1),
    _padding0: [656]u8 align(1),
    header_hash: [64]u8 align(1),
};

pub const SqPackIndex1TableEntry = extern struct {
    const Self = @This();

    hash_data: u64 align(1),
    packed_data: u32 align(1),
    _padding0: u32 align(1),

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

    hash_data: u32 align(1),
    packed_data: u32 align(1),

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

pub const FileType = enum(u32) {
    empty = 0x1,
    standard = 0x2,
    model = 0x3,
    texture = 0x4,
    _,
};

pub const FileInfo = extern struct {
    header_size: u32 align(1),
    file_type: FileType align(1),
    file_size: u32 align(1),
};

pub const StandardFileInfo = extern struct {
    _padding0: [8]u8 align(1),
    num_of_blocks: u32 align(1),
};

pub const TextureFileInfo = StandardFileInfo;

pub const ModelFileInfo = extern struct {
    pub const LodLevels = 3;

    num_of_blocks: u32 align(1),
    used_num_of_blocks: u32 align(1),
    version: u32 align(1),

    uncompressed_size: ModelFileMemorySizes(u32, LodLevels) align(1),
    compressed_size: ModelFileMemorySizes(u32, LodLevels) align(1),
    offset: ModelFileMemorySizes(u32, LodLevels) align(1),
    index: ModelFileMemorySizes(u16, LodLevels) align(1),
    num: ModelFileMemorySizes(u16, LodLevels) align(1),

    vertex_declaration_num: u16 align(1),
    material_num: u16,
    num_lods: u8,

    index_buffer_streaming_enabled: bool align(1),
    edge_geometry_enabled: bool align(1),
};

pub const StandardFileBlockInfo = extern struct {
    offset: u32 align(1),
    compressed_size: u16 align(1),
    uncompressed_size: u16 align(1),
};

pub const TextureFileBlockInfo = extern struct {
    compressed_offset: u32 align(1),
    compressed_size: u32 align(1),
    decompressed_size: u32 align(1),
    block_offset: u32 align(1),
    block_count: u32 align(1),
};

pub const BlockType = enum(u32) {
    compressed = 16000,
    uncompressed = 32000,
    _,
};

pub const BlockHeader = extern struct {
    size: u32 align(1),
    _padding0: u32 align(1),
    block_type: BlockType align(1),
    data_size: u32 align(1),
};

fn ModelFileMemorySizes(comptime T: type, comptime count: usize) type {
    return extern struct {
        const Self = @This();

        stack_size: T align(1),
        runtime_size: T align(1),

        vertex_buffer_size: [count]T align(1),
        edge_geometry_vertex_buffer_size: [count]T align(1),
        index_buffer_size: [count]T align(1),

        pub fn calculateTotal(self: *const Self) T {
            var total: T = 0;
            total += self.stack_size;
            total += self.runtime_size;

            for (self.vertex_buffer_size) |size| {
                total += size;
            }
            for (self.edge_geometry_vertex_buffer_size) |size| {
                total += size;
            }
            for (self.index_buffer_size) |size| {
                total += size;
            }

            return total;
        }
    };
}
