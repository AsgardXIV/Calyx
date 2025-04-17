const std = @import("std");

const calyx = @import("calyx");

test "tex header" {
    std.log.info("Testing basic tex header", .{});

    const game_data = try calyx.GameData.init(std.testing.allocator, .{});
    defer game_data.deinit();

    {
        const tex_file = try game_data.getTypedFile(std.testing.allocator, calyx.game.formats.Tex, "chara/equipment/e6202/texture/v01_c0101e6202_top_mask.tex");
        defer tex_file.deinit();

        try std.testing.expectEqual(.bc1, tex_file.header.format);
        try std.testing.expectEqual(512, tex_file.header.width);
        try std.testing.expectEqual(1024, tex_file.header.height);
    }

    {
        const tex_file = try game_data.getTypedFile(std.testing.allocator, calyx.game.formats.Tex, "chara/equipment/e6202/texture/v01_c0101e6202_top_id.tex");
        defer tex_file.deinit();

        try std.testing.expectEqual(.bc5, tex_file.header.format);
        try std.testing.expectEqual(512, tex_file.header.width);
        try std.testing.expectEqual(1024, tex_file.header.height);
    }
}
