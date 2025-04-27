const std = @import("std");
const Allocator = std.mem.Allocator;

const math = @import("../../core/math.zig");

const FixedBufferStream = std.io.FixedBufferStream([]const u8);

const Sklb = @This();

allocator: Allocator,

sklb_data: SklbData,

layers: SklbLayers,

havok_data: []const u8,

pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !*Sklb {
    const skl = try allocator.create(Sklb);
    errdefer allocator.destroy(skl);

    skl.allocator = allocator;

    const reader = fbs.reader();

    // Header
    const header = try reader.readStruct(SklbHeader);
    try header.validateMagic();

    // Data
    skl.sklb_data = try SklbData.init(allocator, header, fbs);
    errdefer skl.sklb_data.deinit(allocator);

    // Layers
    skl.layers = try SklbLayers.init(allocator, fbs);
    errdefer skl.layers.deinit(allocator);

    // Havok data
    const havok_offset = skl.sklb_data.getHavokOffset();
    const havok_length = try fbs.getEndPos() - havok_offset;
    skl.havok_data = try allocator.dupe(u8, fbs.buffer[havok_offset .. havok_offset + havok_length]);
    errdefer allocator.free(skl.havok_data);

    return skl;
}

pub fn deinit(skl: *Sklb) void {
    skl.allocator.free(skl.havok_data);
    skl.layers.deinit(skl.allocator);
    skl.sklb_data.deinit(skl.allocator);
    skl.allocator.destroy(skl);
}

const SkeletonId = extern struct {
    id: i16,
    unknown: i16,
};

const SklbData = union(enum) {
    v1: SklbDataV1,
    v2: SklbDataV2,

    pub fn init(allocator: Allocator, header: SklbHeader, fbs: *FixedBufferStream) !SklbData {
        switch (header.version_2) {
            0x3132 => return .{
                .v1 = try SklbDataV1.init(allocator, fbs),
            },
            0x3133 => return .{
                .v2 = try SklbDataV2.init(allocator, fbs),
            },
            else => return error.InvalidVersion,
        }
    }

    pub fn deinit(self: *SklbData, allocator: Allocator) void {
        switch (self.*) {
            .v1 => self.v1.deinit(allocator),
            .v2 => self.v2.deinit(allocator),
        }
    }

    pub fn getHavokOffset(self: *SklbData) u32 {
        switch (self.*) {
            .v1 => return self.v1.havok_offset,
            .v2 => return self.v2.havok_offset,
        }
    }
};

const SklbDataV1 = extern struct {
    layer_offset: u16 align(1),
    havok_offset: u16 align(1),
    skeleton_ids: SkeletonId align(1),
    parent_skeleton_ids: [4]SkeletonId align(1),
    lod_bones: [3]i16 align(1),
    connect_bones: [4]i16 align(1),

    pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !SklbDataV1 {
        _ = allocator;
        return fbs.reader().readStruct(SklbDataV1);
    }

    pub fn deinit(self: *SklbDataV1, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }
};

const SklbDataV2 = struct {
    data_size: u32,
    havok_offset: u32,

    bone_connect_idx: i16,
    _unk1: i16,
    skeleton_id: SkeletonId,
    parent_skeleton_ids: std.ArrayListUnmanaged(SkeletonId),

    pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !SklbDataV2 {
        const reader = fbs.reader();

        const data_size = try reader.readInt(u32, .little);
        const havok_offset = try reader.readInt(u32, .little);

        const bone_connect_idx = try reader.readInt(i16, .little);
        const _unk1 = try reader.readInt(i16, .little);
        const skeleton_id = try reader.readStruct(SkeletonId);

        const num_parents = (data_size - 0x18) / @sizeOf(SkeletonId);

        var parent_skeleton_ids: std.ArrayListUnmanaged(SkeletonId) = .{};
        try parent_skeleton_ids.ensureTotalCapacity(allocator, num_parents);
        errdefer parent_skeleton_ids.deinit(allocator);

        for (0..num_parents) |_| {
            const parent_id = try reader.readStruct(SkeletonId);
            parent_skeleton_ids.appendAssumeCapacity(parent_id);
        }

        try fbs.seekTo(math.padTo(fbs.pos, 16));

        return .{
            .data_size = data_size,
            .havok_offset = havok_offset,
            .bone_connect_idx = bone_connect_idx,
            ._unk1 = _unk1,
            .skeleton_id = skeleton_id,
            .parent_skeleton_ids = parent_skeleton_ids,
        };
    }

    pub fn deinit(self: *SklbDataV2, allocator: Allocator) void {
        self.parent_skeleton_ids.deinit(allocator);
    }
};

const SklbLayers = struct {
    const expected_magic = "hpla";

    magic: [4]u8,
    layers: std.ArrayListUnmanaged(SklbLayer),

    pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !SklbLayers {
        const reader = fbs.reader();

        var layers: SklbLayers = .{
            .magic = undefined,
            .layers = .{},
        };
        errdefer layers.deinit(allocator);

        _ = try reader.read(&layers.magic);

        if (!std.mem.eql(u8, &layers.magic, expected_magic)) {
            return error.InvalidMagic;
        }

        const num_layers = try reader.readInt(u16, .little);
        for (0..num_layers) |_| {
            _ = try reader.readInt(u16, .little);
        }

        try layers.layers.ensureTotalCapacity(allocator, num_layers);

        for (0..num_layers) |_| {
            const layer = try SklbLayer.init(allocator, fbs);
            layers.layers.appendAssumeCapacity(layer);
        }

        return layers;
    }

    pub fn deinit(self: *SklbLayers, allocator: Allocator) void {
        for (self.layers.items) |*layer| {
            layer.deinit(allocator);
        }
        self.layers.deinit(allocator);
    }
};

const SklbLayer = struct {
    id: u32,
    bone_ids: std.ArrayListUnmanaged(u16),

    pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !SklbLayer {
        const reader = fbs.reader();

        const id = try reader.readInt(u32, .little);

        var layer: SklbLayer = .{
            .id = id,
            .bone_ids = .{},
        };
        errdefer layer.deinit(allocator);

        const num_bones = try reader.readInt(u16, .little);

        try layer.bone_ids.ensureTotalCapacity(allocator, num_bones);

        for (0..num_bones) |_| {
            const bone_id = try reader.readInt(u16, .little);
            layer.bone_ids.appendAssumeCapacity(bone_id);
        }

        return layer;
    }

    pub fn deinit(self: *SklbLayer, allocator: Allocator) void {
        self.bone_ids.deinit(allocator);
    }
};

const SklbHeader = extern struct {
    const expected_magic = "blks";

    magic: [4]u8 align(1),
    version_1: u16 align(1),
    version_2: u16 align(1),

    pub fn validateMagic(self: *const SklbHeader) !void {
        if (!std.mem.eql(u8, &self.magic, expected_magic)) {
            return error.InvalidMagic;
        }
    }
};
