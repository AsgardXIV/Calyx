const std = @import("std");
const Allocator = std.mem.Allocator;

const Pack = @import("../sqpack/Pack.zig");

const ExcelHeader = @import("ExcelHeader.zig");
const ExcelSheet = @import("ExcelSheet.zig");

const Language = @import("../language.zig").Language;

const meta = @import("../../core/meta.zig");

const ExcelSheetContainer = @This();

const LanguageArraySize = meta.maxEnumValue(Language) + 1;

allocator: Allocator,
pack: *Pack,
sheet_name: []const u8,
excel_header: *ExcelHeader,
excel_sheets: [LanguageArraySize]?*ExcelSheet,

pub fn init(allocator: Allocator, pack: *Pack, sheet_name: []const u8) !*ExcelSheetContainer {
    const container = try allocator.create(ExcelSheetContainer);
    errdefer allocator.destroy(container);

    const sheet_name_dupe = try allocator.dupe(u8, sheet_name);
    errdefer allocator.free(sheet_name_dupe);

    container.* = .{
        .allocator = allocator,
        .pack = pack,
        .sheet_name = sheet_name_dupe,
        .excel_header = undefined,
        .excel_sheets = [_]?*ExcelSheet{null} ** LanguageArraySize,
    };

    try container.loadExcelHeader();

    return container;
}

pub fn deinit(container: *ExcelSheetContainer) void {
    for (container.excel_sheets) |sheet| {
        if (sheet) |s| s.deinit();
    }
    container.allocator.free(container.sheet_name);
    container.excel_header.deinit();
    container.allocator.destroy(container);
}

pub fn getSheetByLanguage(container: *ExcelSheetContainer, language: Language, language_fallback: bool) !*ExcelSheet {
    const actual_language = try blk: {
        if (container.excel_header.hasLanguage(language)) break :blk language;
        if (!language_fallback) break :blk error.LanguageSheetNotFound;
        if (container.excel_header.hasNoneLanguage()) break :blk Language.none;
        break :blk container.excel_header.languages[0];
    };

    const language_index = @intFromEnum(actual_language);

    if (container.excel_sheets[language_index] == null) {
        container.excel_sheets[language_index] = try ExcelSheet.init(container.allocator, container, actual_language);
    }

    return container.excel_sheets[language_index].?;
}

fn loadExcelHeader(container: *ExcelSheetContainer) !void {
    var sfb = std.heap.stackFallback(1024, container.allocator);
    const sfa = sfb.get();

    const sheet_path = try std.fmt.allocPrint(sfa, "exd/{s}.exh", .{container.sheet_name});
    defer sfa.free(sheet_path);

    const excel_header = try container.pack.getTypedFile(container.allocator, ExcelHeader, sheet_path);
    errdefer excel_header.deinit();

    container.excel_header = excel_header;
}
