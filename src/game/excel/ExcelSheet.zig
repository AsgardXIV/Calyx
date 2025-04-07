const std = @import("std");
const Allocator = std.mem.Allocator;

const Language = @import("../language.zig").Language;

const ExcelSheetContainer = @import("ExcelSheetContainer.zig");

const ExcelSheet = @This();

allocator: Allocator,
container: *ExcelSheetContainer,
language: Language,

pub fn init(allocator: Allocator, container: *ExcelSheetContainer, language: Language) !*ExcelSheet {
    const sheet = try allocator.create(ExcelSheet);
    errdefer allocator.destroy(sheet);

    sheet.* = .{
        .allocator = allocator,
        .container = container,
        .language = language,
    };

    return sheet;
}

pub fn deinit(sheet: *ExcelSheet) void {
    sheet.allocator.destroy(sheet);
}
