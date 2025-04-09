const std = @import("std");

const calyx_lib = @import("calxy");
const base = @import("test_base.zig");

test "excel" {
    const calyx = try base.startCalyx();
    defer calyx.deinit();

    // Basic default row
    {
        std.log.info("Testing basic excel row", .{});

        const sheet = try calyx.excel_system.getSheet("ActionTimeline");
        const row = try sheet.getRow(3);

        const expected = "normal/idle";
        try std.testing.expectEqualStrings(expected, row.columns[6].string);
    }

    // Basic sub row
    {
        std.log.info("Testing sub excel row", .{});

        const sheet = try calyx.excel_system.getSheet("QuestDefineClient");
        const row = try sheet.getSubRow(70198, 8);

        const expected = "AGI";
        try std.testing.expectEqualStrings(expected, row.columns[0].string);
    }

    // Default row not found
    {
        std.log.info("Testing default row not found", .{});

        const sheet = try calyx.excel_system.getSheet("ActivityFeedButtons");
        const row = sheet.getRow(500);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, row);
    }

    // Sub row parent row not found
    {
        std.log.info("Testing sub row parent row not found", .{});

        const sheet = try calyx.excel_system.getSheet("QuestDefineClient");
        const row = sheet.getSubRow(50, 0);

        const expected = error.RowNotFound;
        try std.testing.expectError(expected, row);
    }

    // Sub row sub row not found
    {
        std.log.info("Testing sub row sub row not found", .{});

        const sheet = try calyx.excel_system.getSheet("QuestDefineClient");
        const row = sheet.getSubRow(70198, 50);

        const expected = error.SubRowNotFound;
        try std.testing.expectError(expected, row);
    }

    // Default sheet as subrow sheet
    {
        std.log.info("Testing using default sheet as sub row sheet", .{});

        const sheet = try calyx.excel_system.getSheet("ActionTimeline");
        const row = sheet.getSubRow(70198, 50);

        const expected = error.InvalidSheetType;
        try std.testing.expectError(expected, row);
    }

    // Subrow sheet as default row sheet
    {
        std.log.info("Testing sub row sheet as default sheet", .{});

        const sheet = try calyx.excel_system.getSheet("QuestDefineClient");
        const row = sheet.getRow(0);

        const expected = error.InvalidSheetType;
        try std.testing.expectError(expected, row);
    }
}
