const std = @import("std");
const Allocator = std.mem.Allocator;

const Pack = @import("../sqpack/Pack.zig");

const ExcelHeader = @import("ExcelHeader.zig");

const ExcelSheetContainer = @This();

allocator: Allocator,
pack: *Pack,
sheet_name: []const u8,
excel_header: *ExcelHeader,

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
    };

    try container.loadExcelHeader();

    return container;
}

pub fn deinit(container: *ExcelSheetContainer) void {
    container.allocator.free(container.sheet_name);
    container.excel_header.deinit();
    container.allocator.destroy(container);
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
