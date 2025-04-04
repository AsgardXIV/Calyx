const std = @import("std");

const Platform = @import("../common/platform.zig").Platform;

pub const SqPackHeader = extern struct {
    const Self = @This();
    const expected_magic = [8]u8{ 'S', 'q', 'P', 'a', 'c', 'k', 0, 0 };

    magic: [8]u8,
    platform: Platform,
    _padding0: [3]u8,
    size: u32,
    version: u32,
    pack_type: u32,

    pub fn validateMagic(self: *const Self) !void {
        if (std.mem.eql(u8, &self.magic, &expected_magic)) {
            return;
        } else {
            return error.InvalidMagic;
        }
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
    header_size: u32,
    file_type: FileType,
    file_size: u32,
};

pub const StandardFileInfo = extern struct {
    _padding0: [8]u8,
    num_of_blocks: u32,
};

pub const TextureFileInfo = StandardFileInfo;

pub const ModelFileInfo = extern struct {
    pub const lod_levels = 3;

    num_of_blocks: u32,
    used_num_of_blocks: u32,
    version: u32,

    uncompressed_size: ModelFileMemorySizes(u32, lod_levels),
    compressed_size: ModelFileMemorySizes(u32, lod_levels),
    offset: ModelFileMemorySizes(u32, lod_levels),
    index: ModelFileMemorySizes(u16, lod_levels),
    num: ModelFileMemorySizes(u16, lod_levels),

    vertex_declaration_num: u16,
    material_num: u16,
    num_lods: u8,

    index_buffer_streaming_enabled: bool,
    edge_geometry_enabled: bool,
};

pub const StandardFileBlockInfo = extern struct {
    offset: u32,
    compressed_size: u16,
    uncompressed_size: u16,
};

pub const TextureFileBlockInfo = extern struct {
    compressed_offset: u32,
    compressed_size: u32,
    decompressed_size: u32,
    block_offset: u32,
    block_count: u32,
};

pub const BlockType = enum(u32) {
    compressed = 16000,
    uncompressed = 32000,
    _,
};

pub const BlockHeader = extern struct {
    size: u32,
    _padding0: u32,
    block_type: BlockType,
    data_size: u32,
};

fn ModelFileMemorySizes(comptime T: type, comptime count: usize) type {
    return extern struct {
        const Self = @This();

        stack_size: T,
        runtime_size: T,

        vertex_buffer_size: [count]T,
        edge_geometry_vertex_buffer_size: [count]T,
        index_buffer_size: [count]T,

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
