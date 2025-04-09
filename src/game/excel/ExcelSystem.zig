const std = @import("std");
const Allocator = std.mem.Allocator;

const Language = @import("../language.zig").Language;
const Pack = @import("../sqpack/Pack.zig");

const ExcelList = @import("ExcelList.zig");
const ExcelSheet = @import("ExcelSheet.zig");

const string = @import("../../core/string.zig");

const ExcelSystem = @This();

allocator: Allocator,
preferred_language: Language,
pack: *Pack,
root_sheet_list: ?*ExcelList,
sheet_map: std.StringHashMapUnmanaged(*ExcelSheet),

pub fn init(allocator: Allocator, preferred_language: Language, pack: *Pack) !*ExcelSystem {
    const system = try allocator.create(ExcelSystem);
    errdefer allocator.destroy(system);

    system.* = .{
        .allocator = allocator,
        .preferred_language = preferred_language,
        .pack = pack,
        .root_sheet_list = null,
        .sheet_map = .{},
    };

    return system;
}

pub fn deinit(system: *ExcelSystem) void {
    system.cleanupSheets();

    if (system.root_sheet_list) |sheet_list| sheet_list.deinit();

    system.allocator.destroy(system);
}

pub fn getSheet(system: *ExcelSystem, sheet_name: []const u8) !*ExcelSheet {
    return getOrCreateSheetEntry(system, sheet_name);
}

/// Discovers and loads the root list of sheets from the pack.
pub fn discoverDefaultDefinitions(system: *ExcelSystem) !void {
    // First we load the root list
    try system.loadRootList();

    // Cache them all
    var it = system.root_sheet_list.?.id_to_key.valueIterator();
    while (it.next()) |value| {
        _ = try getOrCreateSheetEntry(system, value.*);
    }
}

fn getOrCreateSheetEntry(system: *ExcelSystem, sheet_name: []const u8) !*ExcelSheet {
    // We need a lowercase version of the sheet name for the map
    var sfb = std.heap.stackFallback(1024, system.allocator);
    const sfa = sfb.get();
    const name_lower = try string.allocToLowerCase(sfa, sheet_name);
    defer sfa.free(name_lower);

    // Check if the sheet is already cached
    if (system.sheet_map.get(name_lower)) |sheet| {
        return sheet;
    }

    // We store the sheet name for lookups in lowercase to avoid case sensitivity issues
    const global_name_lower = try system.allocator.dupe(u8, name_lower);
    errdefer system.allocator.free(global_name_lower);

    // Create a new sheet container, we pass the cased version for the name here
    const sheet = try ExcelSheet.init(system.allocator, system.pack, sheet_name, system.preferred_language);
    errdefer sheet.deinit();

    // Store the sheet container in the map
    try system.sheet_map.put(system.allocator, global_name_lower, sheet);

    return sheet;
}

fn loadRootList(system: *ExcelSystem) !void {
    // Destroy the previous root list if it exists
    if (system.root_sheet_list) |sheet_list| {
        sheet_list.deinit();
    }

    // Load the root list
    const root_path = "exd/root.exl";
    const root_list = try system.pack.getTypedFile(system.allocator, ExcelList, root_path);
    errdefer root_list.deinit();
    system.root_sheet_list = root_list;
}

fn cleanupSheets(system: *ExcelSystem) void {
    var it = system.sheet_map.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit();
        system.allocator.free(entry.key_ptr.*);
    }
    system.sheet_map.deinit(system.allocator);
    system.sheet_map = .{};
}
