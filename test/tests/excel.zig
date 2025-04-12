const std = @import("std");

const calyx = @import("calyx");

test "excel" {
    const game_data = try calyx.GameData.init(std.testing.allocator, .{});
    defer game_data.deinit();

    {
        std.log.info("Testing ExcelList", .{});
        const excel_module = game_data.excel;
        try excel_module.loadRootList();

        // Exists
        try std.testing.expectEqualStrings("Tribe", excel_module.root_sheet_list.?.getKeyForId(58).?);

        // Does not exist
        try std.testing.expectEqual(null, excel_module.root_sheet_list.?.getKeyForId(696969));

        // Exists
        try std.testing.expect(excel_module.root_sheet_list.?.hasSheet("guild_order/GuildOrderGuide"));

        // Does not exist
        try std.testing.expect(!excel_module.root_sheet_list.?.hasSheet("does_not_exist"));
    }

    // Basic default row integer
    {
        std.log.info("Testing default excel row integer", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRawRow(23992);
        const val = try row.getRowColumnValue(u16, 30);

        const expected = 1671;
        try std.testing.expectEqual(expected, val);
    }

    // Basic default row float
    {
        std.log.info("Testing default excel row float", .{});

        const sheet = try game_data.getSheet("ModelChara");
        const row = try sheet.getRawRow(11);
        const val = try row.getRowColumnValue(f32, 20);

        const expected = 4.3654;
        try std.testing.expectApproxEqAbs(expected, val, 0.00001);
    }

    // Basic default row packed bool
    {
        std.log.info("Testing default row packed bool", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRawRow(23992);
        const should_be_true = try row.getRowColumnValue(bool, 23);
        const should_be_false = try row.getRowColumnValue(bool, 24);

        try std.testing.expectEqual(true, should_be_true);
        try std.testing.expectEqual(false, should_be_false);
    }

    // Basic default row string
    {
        std.log.info("Testing default row string", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRawRow(23992);
        const val = try row.getRowColumnValue([]const u8, 9);

        const expected = "Wind-up G'raha Tia";
        try std.testing.expectEqualStrings(expected, val);
    }

    // Basic sub row integer
    {
        std.log.info("Testing sub row integer", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRawRow(70198);
        const val = try row.getSubRowColumnValue(u32, 8, 1);

        const expected = 9623609;
        try std.testing.expectEqual(expected, val);
    }

    // Basic sub row string
    {
        std.log.info("Testing sub row string", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRawRow(70198);
        const val = try row.getSubRowColumnValue([]const u8, 8, 0);

        const expected = "AGI";
        try std.testing.expectEqualStrings(expected, val);
    }

    // Default row not found
    {
        std.log.info("Testing default row not found", .{});

        const sheet = try game_data.getSheet("ActivityFeedButtons");
        const row = sheet.getRawRow(500);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, row);
    }

    // Sub row parent row not found
    {
        std.log.info("Testing sub row parent row not found", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = sheet.getRawRow(50);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, row);
    }

    // Sub row sub row not found
    {
        std.log.info("Testing sub row sub row not found", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRawRow(70198);
        const sub_row = row.getSubRowColumnValue(u32, 100, 1);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, sub_row);
    }

    // Using default row as sub row
    {
        std.log.info("Testing default row as sub row", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRawRow(23992);
        const sub_row = row.getSubRowColumnValue(u32, 0, 0);

        const expected = error.InvalidSheetType;
        try std.testing.expectError(expected, sub_row);
    }

    // Using sub row as default row
    {
        std.log.info("Testing sub row as default row", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRawRow(70198);
        const sub_row = row.getRowColumnValue(u32, 1);

        const expected = error.InvalidSheetType;
        try std.testing.expectError(expected, sub_row);
    }

    // Column type mismatch
    {
        std.log.info("Testing column type mismatch", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRawRow(23992);
        const sub_row = row.getRowColumnValue(u32, 2);

        const expected = error.ColumnTypeMismatch;
        try std.testing.expectError(expected, sub_row);
    }

    // Column out of bounds
    {
        std.log.info("Testing column out of bounds", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRawRow(23992);
        const sub_row = row.getRowColumnValue(u32, 500);

        const expected = error.InvalidColumnId;
        try std.testing.expectError(expected, sub_row);
    }
}
