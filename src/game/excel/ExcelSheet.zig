const std = @import("std");
const Allocator = std.mem.Allocator;

const Language = @import("../language.zig").Language;

const ExcelSheetContainer = @import("ExcelSheetContainer.zig");
const ExcelDataFile = @import("ExcelDataFile.zig");

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

    try sheet.populate();

    return sheet;
}

pub fn deinit(sheet: *ExcelSheet) void {
    sheet.allocator.destroy(sheet);
}

fn loadSheetData(sheet: *ExcelSheet, start_id: u32) !void {
    var sfb = std.heap.stackFallback(1024, sheet.allocator);
    const sfa = sfb.get();

    const sheet_path = if (sheet.language == Language.none)
        try std.fmt.allocPrint(sfa, "exd/{s}_{d}.exd", .{ sheet.container.sheet_name, start_id })
    else
        try std.fmt.allocPrint(sfa, "exd/{s}_{d}_{s}.exd", .{ sheet.container.sheet_name, start_id, sheet.language.toLanguageString() });
    defer sfa.free(sheet_path);

    const data = try sheet.container.pack.getTypedFile(sheet.allocator, ExcelDataFile, sheet_path);
    defer data.deinit();
}

fn populate(sheet: *ExcelSheet) !void {
    for (sheet.container.excel_header.page_definitions) |*page| {
        try sheet.loadSheetData(page.start_id);
    }
}
