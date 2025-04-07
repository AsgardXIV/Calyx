const std = @import("std");
const Allocator = std.mem.Allocator;

const Pack = @import("../sqpack/Pack.zig");
const Language = @import("../language.zig").Language;

const ExcelHeader = @import("ExcelHeader.zig");

const ExcelSystem = @This();

allocator: Allocator,
preferred_language: Language,
pack: *Pack,

pub fn init(allocator: Allocator, preferred_language: Language, pack: *Pack) !*ExcelSystem {
    const system = try allocator.create(ExcelSystem);
    errdefer allocator.destroy(system);

    system.* = .{
        .allocator = allocator,
        .preferred_language = preferred_language,
        .pack = pack,
    };

    return system;
}

pub fn deinit(system: *ExcelSystem) void {
    system.allocator.destroy(system);
}

pub fn getSheet(system: *ExcelSystem, sheet_name: []const u8) !void {
    var sfb = std.heap.stackFallback(2048, system.allocator);
    const sfa = sfb.get();

    const sheet_path = try std.fmt.allocPrint(sfa, "exd/{s}.exh", .{sheet_name});
    defer sfa.free(sheet_path);

    const sheet_file = try system.pack.getTypedFile(system.allocator, ExcelHeader, sheet_path);
    defer sheet_file.deinit();
}
