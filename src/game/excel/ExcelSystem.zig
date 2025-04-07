const std = @import("std");
const Allocator = std.mem.Allocator;

const Pack = @import("../sqpack/Pack.zig");
const Language = @import("../language.zig").Language;

const ExcelList = @import("ExcelList.zig");
const ExcelHeader = @import("ExcelHeader.zig");
const ExcelSheetContainer = @import("ExcelSheetContainer.zig");

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
            system.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
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
        _ = try system.getOrCreateSheet(sheet_name);
    }
}

pub fn getOrCreateSheet(system: *ExcelSystem, sheet_name: []const u8) !*ExcelSheetContainer {
    // Check if the sheet is already cached
    if (system.sheet_map.get(sheet_name)) |sheet_container| {
        return sheet_container;
    }

    // We store the sheet name for lookups in lowercase to avoid case sensitivity issues
    const name_lower = try string.allocToLowerCase(system.allocator, sheet_name);
    errdefer system.allocator.free(name_lower);

    // Create a new sheet container, we pass the cased version for the name here
    const sheet_container = try ExcelSheetContainer.init(system.allocator, system.pack, sheet_name);
    errdefer sheet_container.deinit();

    // Store the sheet container in the map
    try system.sheet_map.put(system.allocator, name_lower, sheet_container);

    return sheet_container;
}

pub fn getOrCreateSheetById(system: *ExcelSystem, id: i32) !*ExcelSheetContainer {
    if (system.root_sheet_list == null) {
        try system.loadRootList();
    }

    const sheet_name = system.root_sheet_list.?.getKeyForId(id) orelse return error.SheetIdNotFound;

    return system.getOrCreateSheet(sheet_name);
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
