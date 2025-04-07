const std = @import("std");
const Allocator = std.mem.Allocator;

const Pack = @import("../sqpack/Pack.zig");
const Language = @import("../language.zig").Language;

const ExcelList = @import("ExcelList.zig");
const ExcelHeader = @import("ExcelHeader.zig");
const ExcelSheetContainer = @import("ExcelSheetContainer.zig");
const ExcelSheet = @import("ExcelSheet.zig");

const string = @import("../../core//string.zig");

const ExcelSystem = @This();

allocator: Allocator,
preferred_language: Language,
pack: *Pack,
root_sheet_list: ?*ExcelList,
sheet_map: std.StringHashMapUnmanaged(*ExcelSheetContainer),

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
    if (system.root_sheet_list) |sheet_list| sheet_list.deinit();

    // Need to clean up the sheet map
    {
        var it = system.sheet_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();

            system.allocator.free(entry.key_ptr.*);
        }
        system.sheet_map.deinit(system.allocator);
    }

    system.allocator.destroy(system);
}

pub fn precacheSheetDefinitions(system: *ExcelSystem) !void {
    // First we load the root list
    try system.loadRootList();

    // Create a container for each sheet in the root list
    for (system.root_sheet_list.?.id_to_key.values()) |sheet_name| {
        _ = try system.getOrCreateSheetContainer(sheet_name);
    }
}

/// Get a sheet by its name and language.
///
/// If the sheet is already cached, it will return the cached version.
/// If the sheet is not cached, it will load it and return it.
/// If the sheet is not found, it will return an error.
///
/// The `sheet_name` is the name of the sheet such as "ActionTimeline".
///
/// If the `language` is not specified, it will use the preferred language of the system.
///
/// If `fallback` is true, it will fallback to the `none` (or first available) language if the specified language is not found.
/// If `fallback` is false, it will return an error if the specified language is not found.
///
/// The caller is not responsible for freeing the returned sheet.
pub fn getSheetByName(system: *ExcelSystem, sheet_name: []const u8, language: ?Language, fallback: bool) !*ExcelSheet {
    const sheet_container = try system.getOrCreateSheetContainer(sheet_name);
    const actual_language = language orelse system.preferred_language;
    const sheet = try sheet_container.getSheetByLanguage(actual_language, fallback);
    return sheet;
}

/// Get a sheet by its ID.
///
/// Semantics are the same as `getSheetByPath`, but the ID is used to look up the sheet name.
pub fn getSheetById(system: *ExcelSystem, id: i32, language: ?Language, fallback: bool) !*ExcelSheet {
    if (system.root_sheet_list == null) {
        try system.loadRootList();
    }

    const sheet_name = system.root_sheet_list.?.getKeyForId(id) orelse return error.SheetIdNotFound;

    return system.getSheetByName(sheet_name, language, fallback);
}

fn getOrCreateSheetContainer(system: *ExcelSystem, sheet_name: []const u8) !*ExcelSheetContainer {
    // We need a lowercase version of the sheet name for the map
    var sfb = std.heap.stackFallback(1024, system.allocator);
    const sfa = sfb.get();
    const name_lower = try string.allocToLowerCase(sfa, sheet_name);
    defer sfa.free(name_lower);

    // Check if the sheet is already cached
    if (system.sheet_map.get(name_lower)) |sheet_container| {
        return sheet_container;
    }

    // We store the sheet name for lookups in lowercase to avoid case sensitivity issues
    const global_name_lower = try system.allocator.dupe(u8, name_lower);
    errdefer system.allocator.free(global_name_lower);

    // Create a new sheet container, we pass the cased version for the name here
    const sheet_container = try ExcelSheetContainer.init(system.allocator, system.pack, sheet_name);
    errdefer sheet_container.deinit();

    // Store the sheet container in the map
    try system.sheet_map.put(system.allocator, global_name_lower, sheet_container);

    return sheet_container;
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
