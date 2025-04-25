const std = @import("std");

const calyx = @import("calyx");
const meta = calyx.core.meta;

const Tex = calyx.game.formats.Tex;

test "tex header" {
    std.log.info("Testing basic tex header", .{});

    const game_data = try calyx.GameData.init(std.testing.allocator, .{});
    defer game_data.deinit();

    {
        const tex_file = try game_data.getTypedFile(std.testing.allocator, Tex, "chara/equipment/e6202/texture/v01_c0101e6202_top_mask.tex");
        defer tex_file.deinit();

        try std.testing.expectEqual(.bc1, tex_file.header.format);
        try std.testing.expectEqual(512, tex_file.header.width);
        try std.testing.expectEqual(1024, tex_file.header.height);
        try std.testing.expect(meta.enumHasFlag(tex_file.header.attributes, .texture_type_2d));
    }

    {
        const tex_file = try game_data.getTypedFile(std.testing.allocator, Tex, "chara/equipment/e6202/texture/v01_c0101e6202_top_id.tex");
        defer tex_file.deinit();

        try std.testing.expectEqual(.bc5, tex_file.header.format);
        try std.testing.expectEqual(512, tex_file.header.width);
        try std.testing.expectEqual(1024, tex_file.header.height);
        try std.testing.expect(meta.enumHasFlag(tex_file.header.attributes, .texture_type_2d));
    }

    {
        const tex_file = try game_data.getTypedFile(std.testing.allocator, Tex, "ui/icon/002000/002660_hr1.tex");
        defer tex_file.deinit();

        try std.testing.expectEqual(.b5g5r5a1, tex_file.header.format);
        try std.testing.expectEqual(80, tex_file.header.width);
        try std.testing.expectEqual(80, tex_file.header.height);
        try std.testing.expect(meta.enumHasFlag(tex_file.header.attributes, .texture_type_2d));
    }

    {
        const tex_file = try game_data.getTypedFile(std.testing.allocator, Tex, "ui/icon/060000/060223_hr1.tex");
        defer tex_file.deinit();

        try std.testing.expectEqual(.b8g8r8a8, tex_file.header.format);
        try std.testing.expectEqual(64, tex_file.header.width);
        try std.testing.expectEqual(64, tex_file.header.height);
        try std.testing.expect(meta.enumHasFlag(tex_file.header.attributes, .texture_type_2d));
    }

    {
        const tex_file = try game_data.getTypedFile(std.testing.allocator, Tex, "ui/icon/214000/214925_hr1.tex");
        defer tex_file.deinit();

        try std.testing.expectEqual(.b4g4r4a4, tex_file.header.format);
        try std.testing.expectEqual(48, tex_file.header.width);
        try std.testing.expectEqual(64, tex_file.header.height);
        try std.testing.expect(meta.enumHasFlag(tex_file.header.attributes, .texture_type_2d));
    }
}
