const std = @import("std");
const Allocator = std.mem.Allocator;

const Language = @import("../language.zig").Language;
const Pack = @import("../sqpack/Pack.zig");

const ExcelList = @import("ExcelList.zig");
const ExcelSheet = @import("ExcelSheet.zig");

const string = @import("../../core/string.zig");

const ExcelModule = @This();

allocator: Allocator,
preferred_language: Language,
pack: *Pack,
root_sheet_list: ?*ExcelList,
sheet_map: std.StringHashMapUnmanaged(*ExcelSheet),

pub fn init(
    allocator: Allocator,
    preferred_language: Language,
    pack: *Pack,
) !*ExcelModule {
    const excel = try allocator.create(ExcelModule);
    errdefer allocator.destroy(excel);

    // Populate instance
    excel.* = .{
        .allocator = allocator,
        .preferred_language = preferred_language,
        .pack = pack,
        .root_sheet_list = null,
        .sheet_map = .{},
    };

    return excel;
}

pub fn deinit(excel: *ExcelModule) void {
    excel.cleanupSheets();
    if (excel.root_sheet_list) |sheet_list| sheet_list.deinit();
    excel.allocator.destroy(excel);
}

/// Gets a sheet by name, retrieving it from the cache if it is already loaded.
///
/// `sheet_name` is the case-insensitive name of the sheet to get.
///
/// Returns a pointer to the sheet if it exists or was created.
/// The caller is NOT responsible for freeing the sheet.
pub fn getSheet(excel: *ExcelModule, sheet_name: []const u8) !*ExcelSheet {
    // We need a lowercase version of the sheet name for the map
    var sfb = std.heap.stackFallback(1024, excel.allocator);
    const sfa = sfb.get();
    const name_lower = try string.allocToLowerCase(sfa, sheet_name);
    defer sfa.free(name_lower);

    // Check if the sheet is already cached
    if (excel.sheet_map.get(name_lower)) |sheet| {
        return sheet;
    }

    // We store the sheet name for lookups in lowercase to avoid case sensitivity issues
    const global_name_lower = try excel.allocator.dupe(u8, name_lower);
    errdefer excel.allocator.free(global_name_lower);

    // Create a new sheet container, we pass the cased version for the name here
    const sheet = try ExcelSheet.init(excel.allocator, excel.pack, sheet_name, excel.preferred_language);
    errdefer sheet.deinit();

    // Store the sheet container in the map
    try excel.sheet_map.put(excel.allocator, global_name_lower, sheet);

    return sheet;
}

/// Discovers and loads the root list of sheets from the pack.
pub fn discoverDefaultDefinitions(excel: *ExcelModule) !void {
    // First we load the root list if needed
    try excel.loadRootList();

    // Cache them all
    var it = excel.root_sheet_list.?.id_to_key.valueIterator();
    while (it.next()) |value| {
        _ = try excel.getSheet(value.*);
    }
}

/// Loads the root list from the pack.
/// Calling this function will do nothing if the root list is already loaded.
pub fn loadRootList(excel: *ExcelModule) !void {
    // Destroy the previous root list if it exists
    if (excel.root_sheet_list != null) {
        @branchHint(.unlikely);
        return;
    }

    // Load the root list
    const root_path = "exd/root.exl";
    const root_list = try excel.pack.getTypedFile(excel.allocator, ExcelList, root_path);
    errdefer root_list.deinit();
    excel.root_sheet_list = root_list;
}

fn cleanupSheets(excel: *ExcelModule) void {
    var it = excel.sheet_map.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit();
        excel.allocator.free(entry.key_ptr.*);
    }
    excel.sheet_map.deinit(excel.allocator);
    excel.sheet_map = .{};
}
