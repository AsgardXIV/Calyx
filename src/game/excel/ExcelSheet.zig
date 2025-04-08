const std = @import("std");
const Allocator = std.mem.Allocator;

const Language = @import("../language.zig").Language;

const ExcelSheetContainer = @import("ExcelSheetContainer.zig");
const ExcelDataFile = @import("ExcelDataFile.zig");
const ExcelRow = @import("ExcelRow.zig");

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelSheet = @This();

allocator: Allocator,
container: *ExcelSheetContainer,
language: Language,
rows: std.AutoHashMapUnmanaged(u32, ExcelRow),

pub fn init(allocator: Allocator, container: *ExcelSheetContainer, language: Language) !*ExcelSheet {
    const sheet = try allocator.create(ExcelSheet);
    errdefer allocator.destroy(sheet);

    sheet.* = .{
        .allocator = allocator,
        .container = container,
        .language = language,
        .rows = .{},
    };

    try sheet.populate();

    return sheet;
}

pub fn deinit(sheet: *ExcelSheet) void {
    sheet.cleanupRows();
    sheet.allocator.destroy(sheet);
}

pub fn getRow(sheet: *ExcelSheet, row_id: u32) ?ExcelRow {
    return sheet.rows.get(row_id);
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

    try sheet.rows.ensureUnusedCapacity(sheet.allocator, @intCast(data.indexes.len));
    errdefer sheet.cleanupRows();

    var bsr = BufferedStreamReader.initFromConstBuffer(data.raw_sheet_data);
    defer bsr.close();

    for (data.indexes) |*index| {
        const row_data_offset = index.offset - data.data_start;

        const row_value = try ExcelRow.populate(
            sheet.allocator,
            index.row_id,
            row_data_offset,
            sheet.container.excel_header.header.data_offset,
            sheet.container.excel_header.column_definitions,
            &bsr,
        );

        sheet.rows.getOrPutAssumeCapacity(index.row_id).value_ptr.* = row_value;
    }
}

fn populate(sheet: *ExcelSheet) !void {
    for (sheet.container.excel_header.page_definitions) |*page| {
        try sheet.loadSheetData(page.start_id);
    }
}

fn cleanupRows(sheet: *ExcelSheet) void {
    var it = sheet.rows.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.destroy(sheet.allocator);
    }
    sheet.rows.deinit(sheet.allocator);
}
