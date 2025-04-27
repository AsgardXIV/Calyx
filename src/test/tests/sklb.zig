const std = @import("std");

const calyx = @import("calyx");
const meta = calyx.core.meta;

const Sklb = calyx.game.formats.Sklb;

test "sklb" {
    std.log.info("Testing sklb", .{});

    const game_data = try calyx.GameData.init(std.testing.allocator, .{});
    defer game_data.deinit();

    {
        const sklb_file = try game_data.getTypedFile(std.testing.allocator, Sklb, "chara/human/c0701/skeleton/base/b0001/skl_c0701b0001.sklb");
        defer sklb_file.deinit();
    }

    {
        const sklb_file = try game_data.getTypedFile(std.testing.allocator, Sklb, "chara/human/c1801/skeleton/base/b0001/skl_c1801b0001.sklb");
        defer sklb_file.deinit();
    }
}
