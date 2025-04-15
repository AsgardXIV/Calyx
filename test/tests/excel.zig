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
        const row = try sheet.getRow(23992);
        const val = try row.getRowColumnValue(30);

        const expected = 1671;
        try std.testing.expectEqual(expected, val.u16);
    }

    // Basic default row float
    {
        std.log.info("Testing default excel row float", .{});

        const sheet = try game_data.getSheet("ModelChara");
        const row = try sheet.getRow(11);
        const val = try row.getRowColumnValue(20);

        const expected = 4.3654;
        try std.testing.expectApproxEqAbs(expected, val.f32, 0.00001);
    }

    // Basic default row packed bool
    {
        std.log.info("Testing default row packed bool", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRow(23992);
        const should_be_true = try row.getRowColumnValue(23);
        const should_be_false = try row.getRowColumnValue(24);

        try std.testing.expectEqual(true, should_be_true.bool);
        try std.testing.expectEqual(false, should_be_false.bool);
    }

    // Basic default row string
    {
        std.log.info("Testing default row string", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRow(23992);
        const val = try row.getRowColumnValue(9);

        const expected = "Wind-up G'raha Tia";
        try std.testing.expectEqualStrings(expected, val.string);
    }

    // Count default
    {
        std.log.info("Testing count default", .{});

        const sheet = try game_data.getSheet("BuddyAction");
        const count = sheet.getRowCount();

        try std.testing.expectEqual(8, count);
    }

    // Iterate default
    {
        std.log.info("Testing iterate default", .{});

        const sheet = try game_data.getSheet("BuddyAction");
        var it = sheet.rowIterator();
        var counter: u32 = 0;
        while (it.next()) |row| {
            const name = try row.getRowColumnValue(0);
            _ = name;
            counter += 1;
        }

        try std.testing.expectEqual(8, counter);
    }

    // Basic sub row integer
    {
        std.log.info("Testing sub row integer", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRow(70198);
        const val = try row.getSubRowColumnValue(8, 1);

        const expected = 9623609;
        try std.testing.expectEqual(expected, val.u32);
    }

    // Basic sub row string
    {
        std.log.info("Testing sub row string", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRow(70198);
        const val = try row.getSubRowColumnValue(8, 0);

        const expected = "AGI";
        try std.testing.expectEqualStrings(expected, val.string);
    }

    // Default row not found
    {
        std.log.info("Testing default row not found", .{});

        const sheet = try game_data.getSheet("ActivityFeedButtons");
        const row = sheet.getRow(500);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, row);
    }

    // Sub row parent row not found
    {
        std.log.info("Testing sub row parent row not found", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = sheet.getRow(50);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, row);
    }

    // Sub row sub row not found
    {
        std.log.info("Testing sub row sub row not found", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRow(70198);
        const sub_row = row.getSubRowColumnValue(100, 1);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, sub_row);
    }

    // Using default row as sub row
    {
        std.log.info("Testing default row as sub row", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRow(23992);
        const sub_row = row.getSubRowColumnValue(0, 0);

        const expected = error.InvalidSheetType;
        try std.testing.expectError(expected, sub_row);
    }

    // Using sub row as default row
    {
        std.log.info("Testing sub row as default row", .{});

        const sheet = try game_data.getSheet("QuestDefineClient");
        const row = try sheet.getRow(70198);
        const sub_row = row.getRowColumnValue(1);

        const expected = error.InvalidSheetType;
        try std.testing.expectError(expected, sub_row);
    }

    // Column out of bounds
    {
        std.log.info("Testing column out of bounds", .{});

        const sheet = try game_data.getSheet("Item");
        const row = try sheet.getRow(23992);
        const sub_row = row.getRowColumnValue(500);

        const expected = error.InvalidColumnId;
        try std.testing.expectError(expected, sub_row);
    }

    // Test column hash
    {
        std.log.info("Testing column hash", .{});

        const sheet = try game_data.getSheet("BuddyAction");
        const column_hash = sheet.excel_header.getColumnsHash();

        const expected: u32 = 0x9A695BEC;
        try std.testing.expectEqual(expected, column_hash);
    }
}
