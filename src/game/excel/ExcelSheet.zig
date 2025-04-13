const std = @import("std");
const Allocator = std.mem.Allocator;

const ExcelHeader = @import("ExcelHeader.zig");
const ExcelData = @import("ExcelData.zig");
const ExcelRawRow = @import("ExcelRawRow.zig");

const native_types = @import("native_types.zig");
const ExcelDataOffset = native_types.ExcelDataOffset;
const ExcelDataRowPreamble = native_types.ExcelDataRowPreamble;

const Pack = @import("../sqpack/Pack.zig");
const Language = @import("../language.zig").Language;

const ExcelSheet = @This();

const RawRowData = struct {
    data: []const u8,
    row_count: u16,
};

allocator: Allocator,
pack: *Pack,
sheet_name: []const u8,
excel_header: *ExcelHeader,
language: Language,
datas: []?*ExcelData,

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
    };

    try sheet.loadExcelHeader();
    errdefer sheet.excel_header.deinit();

    try sheet.determineLanguage(preferred_language);

    try sheet.allocateDatas();
    errdefer sheet.cleanupDatas();

    return sheet;
}

pub fn deinit(sheet: *ExcelSheet) void {
    sheet.cleanupDatas();
    sheet.excel_header.deinit();
    sheet.allocator.free(sheet.sheet_name);
    sheet.allocator.destroy(sheet);
}

/// Gets the raw row data for a given `row_id`.
///
/// Both default and subrow sheets are supported.
/// See `ExcelRawRow` for more details on how to access columns and subrows.
///
/// No heap allocations are performed in this function.
/// The returned data is valid until the sheet is deinitialized.
pub fn getRawRow(sheet: *ExcelSheet, row_id: u32) !ExcelRawRow {
    // TODO: Do we need an alloc version of this method?

    const page, const offset = try sheet.determineRowPageAndOffset(row_id);
    const data, const row_count = try sliceFromDataAndOffset(page, offset);
    const fixed_size = sheet.excel_header.header.data_offset;

    return .{
        .sheet_type = sheet.excel_header.header.sheet_type,
        .data = data,
        .row_count = row_count,
        .fixed_size = fixed_size,
        .column_definitions = sheet.excel_header.column_definitions,
    };
}

fn sliceFromDataAndOffset(data: *ExcelData, offset: ExcelDataOffset) !struct { []const u8, u16 } {
    var fbs = std.io.fixedBufferStream(data.raw_sheet_data);

    const true_offset = offset.offset - data.data_start;
    try fbs.seekTo(true_offset);

    const row_preamble = try fbs.reader().readStructEndian(ExcelDataRowPreamble, .big);
    const row_size = row_preamble.data_size;

    const first_data = try fbs.getPos();

    const row_buffer = data.raw_sheet_data[first_data .. first_data + row_size];

    return .{ row_buffer, row_preamble.row_count };
}

fn determineRowPageAndOffset(sheet: *ExcelSheet, row_id: u32) !struct { *ExcelData, ExcelDataOffset } {
    const page_index = try sheet.determineRowPage(row_id);
    const data = try sheet.getPageData(page_index);
    const row_index_id = data.row_to_index.get(row_id) orelse return error.RowNotFound;
    const row_offset = data.indexes[row_index_id];
    return .{ data, row_offset };
}

fn determineRowPage(sheet: *ExcelSheet, row_id: u32) !usize {
    for (sheet.excel_header.page_definitions, 0..) |page, i| {
        const page_end = page.start_id + page.row_count;
        if (row_id >= page.start_id and row_id < page_end) {
            return i;
        }
    }
    return error.RowNotFound;
}

fn getPageData(sheet: *ExcelSheet, page_index: usize) !*ExcelData {
    if (sheet.datas[page_index] == null) {
        const data = try sheet.loadPageData(sheet.excel_header.page_definitions[page_index].start_id);
        sheet.datas[page_index] = data;
        return data;
    }

    return sheet.datas[page_index].?;
}

fn loadPageData(sheet: *ExcelSheet, start_row_id: u32) !*ExcelData {
    var sfb = std.heap.stackFallback(1024, sheet.allocator);
    const sfa = sfb.get();

    const sheet_path = if (sheet.language == Language.none)
        try std.fmt.allocPrint(sfa, "exd/{s}_{d}.exd", .{ sheet.sheet_name, start_row_id })
    else
        try std.fmt.allocPrint(sfa, "exd/{s}_{d}_{s}.exd", .{ sheet.sheet_name, start_row_id, sheet.language.toLanguageString() });
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
