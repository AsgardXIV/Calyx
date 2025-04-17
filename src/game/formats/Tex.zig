const std = @import("std");
const Allocator = std.mem.Allocator;

const FixedBufferStream = std.io.FixedBufferStream([]const u8);

const Tex = @This();

allocator: Allocator,
header: TexHeader,
raw_data: []const u8,

pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !*Tex {
    const tex = try allocator.create(Tex);
    errdefer allocator.destroy(tex);

    tex.* = .{
        .allocator = allocator,
        .header = undefined,
        .raw_data = undefined,
    };

    try tex.populate(fbs);

    return tex;
}

pub fn deinit(tex: *Tex) void {
    tex.allocator.free(tex.raw_data);
    tex.allocator.destroy(tex);
}

fn populate(tex: *Tex, fbs: *FixedBufferStream) !void {
    const reader = fbs.reader();

    // Read the header
    tex.header = try reader.readStruct(TexHeader);

    // Read the raw data
    tex.raw_data = try tex.allocator.dupe(u8, fbs.buffer[fbs.pos..]);
}

pub const TexHeader = extern struct {
    attribute: TextureAttribute align(1),
    format: TextureFormat align(1),

    width: u16 align(1),
    height: u16 align(1),
    depth: u16 align(1),
    mip_count: u8 align(1),
    array_size: u8 align(1),

    lod_offsets: [3]u32 align(1),
    offset_to_surface: [13]u32 align(1),
};

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
    texture_type_cube = 0x2000000,
    texture_type_mask = 0x3C00000,
    texture_swizzle = 0x4000000,
    texture_no_tiled = 0x8000000,
    texture_no_swizzle = 0x80000000,

    _,
};

pub const TextureFormat = enum(u32) {
    b4g4r4a4 = 0x1440,
    b8g8r8a8 = 0x1450,
    bc1 = 0x3420, // DXT1
    bc2 = 0x3430, // DXT3
    bc3 = 0x3431, // DXT5
    bc5 = 0x6230, // ATI2
    bc7 = 0x6231,
    _,
};
