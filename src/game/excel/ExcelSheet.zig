const std = @import("std");
const Allocator = std.mem.Allocator;

const ExcelHeader = @import("ExcelHeader.zig");
const ExcelData = @import("ExcelData.zig");
const ExcelRow = @import("ExcelRow.zig");

const native_types = @import("native_types.zig");
const ExcelDataRowPreamble = native_types.ExcelDataRowPreamble;

const Pack = @import("../sqpack/Pack.zig");

const Language = @import("../language.zig").Language;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelSheet = @This();

const SubRow = extern struct {
    row_id: u32,
    sub_row_id: u32,
};

allocator: Allocator,
pack: *Pack,
sheet_name: []const u8,
excel_header: *ExcelHeader,
language: Language,
datas: []?*ExcelData,
rows: std.AutoHashMapUnmanaged(u32, ExcelRow),
sub_rows: std.AutoHashMapUnmanaged(SubRow, ExcelRow),

pub fn init(allocator: Allocator, pack: *Pack, sheet_name: []const u8, preferred_language: Language) !*ExcelSheet {
    const sheet = try allocator.create(ExcelSheet);
    errdefer allocator.destroy(sheet);

    const sheet_name_dupe = try allocator.dupe(u8, sheet_name);
    errdefer allocator.free(sheet_name_dupe);

    sheet.* = .{
        .allocator = allocator,
        .pack = pack,
        .sheet_name = sheet_name_dupe,
        .excel_header = undefined,
        .language = undefined,
        .datas = undefined,
        .rows = .{},
        .sub_rows = .{},
    };

    try sheet.loadExcelHeader();
    errdefer sheet.excel_header.deinit();

    try sheet.allocateDatas();
    errdefer sheet.cleanupDatas();

    try sheet.determineLanguage(preferred_language);

    return sheet;
}

pub fn deinit(sheet: *ExcelSheet) void {
    sheet.cleanupRows();
    sheet.cleanupDatas();
    sheet.excel_header.deinit();
    sheet.allocator.free(sheet.sheet_name);
    sheet.allocator.destroy(sheet);
}

/// Get's the specified `row` from the sheet.
///
/// If the row is already cached, it will return the cached version.
/// If the row is not cached, it will load it and return it.
/// If the row is not found, it will return an error.
///
/// Will return an error if the sheet is not of the default type.
///
/// The caller is not responsible for freeing the returned row.
pub fn getRow(sheet: *ExcelSheet, row: u32) !ExcelRow {
    if (sheet.excel_header.header.sheet_type != .default) {
        return error.InvalidSheetType;
    }

    if (sheet.rows.get(row)) |row_value| {
        return row_value;
    }

    const data, const row_offset = try sheet.determinePageAndRowOffset(row);
    const first_column_offset = row_offset + @sizeOf(ExcelDataRowPreamble);
    const extra_offset = first_column_offset + sheet.excel_header.header.data_offset;

    var bsr = BufferedStreamReader.initFromConstBuffer(data.raw_sheet_data);
    defer bsr.close();

    // We don't actually even need the preamble
    //bsr.seekTo(row_offset);
    //const row_preamble = try bsr.readStructEndian(ExcelDataRowPreamble, .big);

    try bsr.seekTo(first_column_offset);

    const result = try ExcelRow.populate(
        sheet.allocator,
        row_offset,
        first_column_offset,
        extra_offset,
        sheet.excel_header.column_definitions,
        &bsr,
    );

    try sheet.rows.put(sheet.allocator, row, result);

    return result;
}

/// Get's the specified `row` and `sub_row` from the sheet.
///
/// If the row is already cached, it will return the cached version.
/// If the row is not cached, it will load it and return it.
/// If the row is not found, it will return an error.
///
/// Will return an error if the sheet is not of the sub-row type.
///
/// The caller is not responsible for freeing the returned row.
pub fn getSubRow(sheet: *ExcelSheet, row: u32, sub_row: u32) !ExcelRow {
    if (sheet.excel_header.header.sheet_type != .sub_rows) {
        return error.InvalidSheetType;
    }

    const sub_row_key = SubRow{
        .row_id = row,
        .sub_row_id = sub_row,
    };

    if (sheet.sub_rows.get(sub_row_key)) |row_value| {
        return row_value;
    }

    const data, const row_offset = try sheet.determinePageAndRowOffset(row);
    const first_column_offset = row_offset + @sizeOf(ExcelDataRowPreamble);

    var bsr = BufferedStreamReader.initFromConstBuffer(data.raw_sheet_data);
    defer bsr.close();

    try bsr.seekTo(row_offset);
    const row_preamble = try bsr.reader().readStructEndian(ExcelDataRowPreamble, .big);

    if (sub_row >= row_preamble.row_count) {
        return error.SubRowNotFound;
    }

    const subrow_offset = first_column_offset + (sub_row * sheet.excel_header.header.data_offset + 2 * (sub_row + 1));
    const extra_offset = subrow_offset + sheet.excel_header.header.data_offset;

    try bsr.seekTo(subrow_offset);

    const result = try ExcelRow.populate(
        sheet.allocator,
        row_offset,
        subrow_offset,
        extra_offset,
        sheet.excel_header.column_definitions,
        &bsr,
    );

    try sheet.sub_rows.put(sheet.allocator, sub_row_key, result);

    return result;
}

/// Returns the number of rows in the sheet.
///
/// This is the indicated size by the game and may contain empty rows.
/// Sub-rows are not included in this count.
pub fn getRowCount(sheet: *ExcelSheet) u32 {
    return sheet.excel_header.header.row_count;
}

/// Returns the number of sub-rows in the specified row.
///
/// This is the indicated size by the game and may contain empty rows.
/// Will return an error if the sheet is not of the sub-row type.
/// Will return an error if the parent row is not found.
pub fn getSubRowCount(sheet: *ExcelSheet, row: u32) !u32 {
    if (sheet.excel_header.header.sheet_type != .sub_rows) {
        return error.InvalidSheetType;
    }

    const data, const row_offset = try sheet.determinePageAndRowOffset(row);

    var bsr = BufferedStreamReader.initFromConstBuffer(data.raw_sheet_data);
    defer bsr.close();

    try bsr.seekTo(row_offset);
    const row_preamble = try bsr.reader().readStructEndian(ExcelDataRowPreamble, .big);

    return row_preamble.row_count;
}

fn loadExcelHeader(sheet: *ExcelSheet) !void {
    var sfb = std.heap.stackFallback(1024, sheet.allocator);
    const sfa = sfb.get();

    const sheet_path = try std.fmt.allocPrint(sfa, "exd/{s}.exh", .{sheet.sheet_name});
    defer sfa.free(sheet_path);

    const excel_header = try sheet.pack.getTypedFile(sheet.allocator, ExcelHeader, sheet_path);
    errdefer excel_header.deinit();

    sheet.excel_header = excel_header;
}

fn determineLanguage(sheet: *ExcelSheet, preferred_language: Language) !void {
    var has_none = false;

    // Try to use the preferred language first
    for (sheet.excel_header.languages) |language| {
        if (language == preferred_language) {
            sheet.language = language;
            return;
        }

        if (language == .none) {
            has_none = true;
        }
    }

    // If the preferred language is not found, use none if available
    if (has_none) {
        sheet.language = .none;
        return;
    }

    // If no compatibile language is found, return an error
    return error.LanguageNotFound;
}

fn determinePageAndRowOffset(sheet: *ExcelSheet, row: u32) !struct { *ExcelData, u32 } {
    const page_index = try sheet.determineRowPage(row);
    const data = try sheet.getPageData(page_index);
    const row_index_id = data.row_to_index.get(row) orelse return error.RowNotFound;
    const row_index = data.indexes[row_index_id];
    const row_offset = row_index.offset - data.data_start;
    return .{ data, row_offset };
}

fn determineRowPage(sheet: *ExcelSheet, row: u32) !usize {
    for (sheet.excel_header.page_definitions, 0..) |page, i| {
        const page_end = page.start_id + page.row_count;
        if (row >= page.start_id and row < page_end) {
            return i;
        }
    }
    return error.RowNotFound;
}

fn getPageData(sheet: *ExcelSheet, page_index: usize) !*ExcelData {
    if (sheet.datas[page_index]) |data| {
        return data;
    }
    const data = try loadSheetData(sheet, sheet.excel_header.page_definitions[page_index].start_id);
    errdefer data.deinit();
    sheet.datas[page_index] = data;
    return data;
}

fn loadSheetData(sheet: *ExcelSheet, start_id: u32) !*ExcelData {
    var sfb = std.heap.stackFallback(1024, sheet.allocator);
    const sfa = sfb.get();

    const sheet_path = if (sheet.language == Language.none)
        try std.fmt.allocPrint(sfa, "exd/{s}_{d}.exd", .{ sheet.sheet_name, start_id })
    else
        try std.fmt.allocPrint(sfa, "exd/{s}_{d}_{s}.exd", .{ sheet.sheet_name, start_id, sheet.language.toLanguageString() });
    defer sfa.free(sheet_path);

    const data = try sheet.pack.getTypedFile(sheet.allocator, ExcelData, sheet_path);
    errdefer data.deinit();

    return data;
}

fn allocateDatas(sheet: *ExcelSheet) !void {
    const num_pages = sheet.excel_header.page_definitions.len;
    sheet.datas = try sheet.allocator.alloc(?*ExcelData, num_pages);
    errdefer sheet.allocator.free(sheet.datas);

    for (sheet.datas) |*data| {
        data.* = null;
    }
}

fn cleanupDatas(sheet: *ExcelSheet) void {
    for (sheet.datas) |*data| {
        if (data.*) |d| {
            d.deinit();
        }
        data.* = null;
    }
    sheet.allocator.free(sheet.datas);
}

fn cleanupRows(sheet: *ExcelSheet) void {
    {
        var it = sheet.rows.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.destroy(sheet.allocator);
        }
        sheet.rows.deinit(sheet.allocator);
    }

    {
        var it = sheet.sub_rows.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.destroy(sheet.allocator);
        }
        sheet.sub_rows.deinit(sheet.allocator);
    }
}
