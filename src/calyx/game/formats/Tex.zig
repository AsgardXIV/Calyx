const std = @import("std");
const Allocator = std.mem.Allocator;

const FixedBufferStream = std.io.FixedBufferStream([]const u8);

const math = @import("../../core/math.zig");

const Tex = @This();

allocator: Allocator,

attributes: TextureAttribute,
format: TextureFormat,

width: u16,
height: u16,
depth: u16,
mip_count: u8,
mip_flag: bool,
array_size: u8,

lod_offsets: [3]u32,
offset_to_surface: [13]u32,

raw_data: []const u8,

pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !*Tex {
    const tex = try allocator.create(Tex);
    errdefer allocator.destroy(tex);

    // Read
    const reader = fbs.reader();
    const header = try reader.readStruct(TexHeader);
    const raw_data = try allocator.dupe(u8, fbs.buffer[fbs.pos..]);
    errdefer allocator.free(raw_data);

    // Populate
    tex.* = .{
        .allocator = allocator,
        .attributes = header.attributes,
        .format = header.format,
        .width = header.width,
        .height = header.height,
        .depth = header.depth,
        .mip_count = header.mip_field & 0x7F,
        .mip_flag = (header.mip_field & 0x80) != 0,
        .array_size = header.array_size,
        .lod_offsets = header.lod_offsets,
        .raw_data = raw_data,

        .offset_to_surface = @splat(0), // We're going to adjust these
    };

    // Adjust the offsets to be relative to the start of the data instead of the start of the header
    const header_size = @sizeOf(TexHeader);
    for (0..tex.mip_count) |mip| {
        tex.offset_to_surface[mip] = header.offset_to_surface[mip] - header_size;
    }

    return tex;
}

pub fn deinit(tex: *Tex) void {
    tex.allocator.free(tex.raw_data);
    tex.allocator.destroy(tex);
}

pub fn getSlice(tex: *Tex, mip_level: u32, index: u32) ![]const u8 {
    const slice_size = try tex.calculateSliceByteSize(mip_level);

    // Sanity check the index
    const valid_index = switch (tex.attributes.getTextureType()) {
        .texture_type_1d, .texture_type_2d => index == 0,
        .texture_type_3d => index < tex.depth,
        .texture_type_2d_array => index < tex.array_size,
        .texture_type_cube => index < 6,
        else => false,
    };

    if (!valid_index) {
        @branchHint(.unlikely);
        return error.InvalidSliceIndex;
    }

    const slice_offset = tex.offset_to_surface[mip_level] + (slice_size * index);

    return tex.raw_data[slice_offset .. slice_offset + slice_size];
}

/// Calculate the size of a single slice given a mip level.
///
/// Returns the size in bytes of the slice at the given mip level.
pub fn calculateSliceByteSize(tex: *Tex, mip_level: u32) !u32 {
    // Sanity check the mip level
    if (mip_level >= tex.mip_count) {
        @branchHint(.unlikely);
        return error.InvalidMipLevel;
    }

    const bpp = tex.format.getBitsPerPixel();

    const compress_type = tex.format.getType();

    const mip_width = @max(1, tex.width >> @intCast(mip_level));
    const mip_height = @max(1, tex.height >> @intCast(mip_level));

    const total_bytes = switch (compress_type) {
        .type_bc123, .type_bc567 => blk: {
            // BCn formats require 4x4 so we can assume they padded to 4
            const adjusted_width = math.padTo(mip_width, 4);
            const adjusted_height = math.padTo(mip_width, 4);

            // Calculate block count
            const blocks_x = adjusted_width / 4;
            const blocks_y = adjusted_height / 4;

            // Each block has 16 texels
            const bytes_per_block = (bpp * 16) / 8;

            // Calculate total bytes
            const total_bytes = blocks_x * blocks_y * bytes_per_block;
            break :blk total_bytes;
        },
        else => blk: {
            const bits_per_row = mip_width * bpp;
            const bytes_per_row = std.math.divCeil(u32, bits_per_row, 8) catch unreachable;
            const total_bytes = bytes_per_row * mip_height;

            break :blk total_bytes;
        },
    };

    return total_bytes;
}

pub const TextureAttribute = enum(u32) {
    discard_per_frame = 0x1,
    discard_per_map = 0x2,

    managed = 0x4,
    user_managed = 0x8,
    cpu_read = 0x10,
    location_main = 0x20,
    no_gpu_read = 0x40,
    aligned_size = 0x80,
    edge_culling = 0x100,
    location_onion = 0x200,
    read_write = 0x400,
    immutable = 0x800,

    texture_render_target = 0x100000,
    texture_depth_stencil = 0x200000,
    texture_type_1d = 0x400000,
    texture_type_2d = 0x800000,
    texture_type_3d = 0x1000000,
    texture_type_2d_array = 0x10000000,
    texture_type_cube = 0x2000000,

    texture_swizzle = 0x4000000,
    texture_no_tiled = 0x8000000,
    texture_no_swizzle = 0x80000000,

    _,

    pub const texture_type_mask = 0x13C00000;

    pub fn getTextureType(self: TextureAttribute) TextureAttribute {
        const raw_value = @intFromEnum(self);
        const raw_result = raw_value & texture_type_mask;
        return @enumFromInt(raw_result);
    }
};

pub const TextureFormat = enum(u32) {
    type_integer = 0x1,
    type_float = 0x2,
    type_bc123 = 0x3,
    type_depth_stencil = 0x4,
    type_bc567 = 0x5,

    b4g4r4a4 = 0x1440,
    b5g5r5a1 = 0x1441,
    b8g8r8a8 = 0x1450,
    bc1 = 0x3420, // DXT1
    bc2 = 0x3430, // DXT3
    bc3 = 0x3431, // DXT5
    bc5 = 0x6230, // ATI2
    bc7 = 0x6432,

    _,

    pub const bits_per_pixel_shift: u32 = 0x4;
    pub const bits_per_pixel_mask: u32 = 0xF0;

    pub const type_shift: u32 = 0xC;
    pub const type_mask: u32 = 0xF000;

    pub fn getBitsPerPixel(self: TextureFormat) u32 {
        const raw_value = @intFromEnum(self);
        const bits = std.math.shr(u32, raw_value & bits_per_pixel_mask, bits_per_pixel_shift);
        return std.math.shl(u32, 1, bits);
    }

    pub fn getType(self: TextureFormat) TextureFormat {
        const raw_value = @intFromEnum(self);
        const raw_result = std.math.shr(u32, raw_value & type_mask, type_shift);
        return @enumFromInt(raw_result);
    }
};

const TexHeader = extern struct {
    attributes: TextureAttribute align(1),
    format: TextureFormat align(1),

    width: u16 align(1),
    height: u16 align(1),
    depth: u16 align(1),
    mip_field: u8 align(1),
    array_size: u8 align(1),

    lod_offsets: [3]u32 align(1),
    offset_to_surface: [13]u32 align(1),
};
