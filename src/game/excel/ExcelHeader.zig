const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelHeaderHeader = native_types.ExcelHeaderHeader;
const ExcelColumnDefinition = native_types.ExcelColumnDefinition;
const ExcelPageDefinition = native_types.ExcelPageDefinition;

const Language = @import("../language.zig").Language;

const FixedBufferStream = std.io.FixedBufferStream([]const u8);

const ExcelHeader = @This();

allocator: Allocator,
header: ExcelHeaderHeader,
column_definitions: []ExcelColumnDefinition,
page_definitions: []ExcelPageDefinition,
languages: []Language,

pub fn init(allocator: Allocator, fbs: *FixedBufferStream) !*ExcelHeader {
    const header = try allocator.create(ExcelHeader);
    errdefer allocator.destroy(header);

    header.* = .{
        .allocator = allocator,
        .header = undefined,
        .column_definitions = undefined,
        .page_definitions = undefined,
        .languages = undefined,
    };

    try header.populate(fbs);

    return header;
}

pub fn deinit(header: *ExcelHeader) void {
    header.allocator.free(header.column_definitions);
    header.allocator.free(header.page_definitions);
    header.allocator.free(header.languages);

    header.allocator.destroy(header);
}

pub fn hasLanguage(header: *ExcelHeader, language: Language) bool {
    for (header.languages) |l| {
        if (l == language) {
            return true;
        }
    }
    return false;
}

pub fn hasNoneLanguage(header: *ExcelHeader) bool {
    return hasLanguage(header, Language.none);
}

fn populate(header: *ExcelHeader, fbs: *FixedBufferStream) !void {
    const reader = fbs.reader();

    // Read the header
    header.header = try reader.readStructEndian(ExcelHeaderHeader, .big);
    try header.header.validateMagic();

    // Read the column definitions
    const column_count = header.header.column_count;
    header.column_definitions = try header.allocator.alloc(ExcelColumnDefinition, column_count);
    errdefer header.allocator.free(header.column_definitions);
    for (header.column_definitions) |*column_definition| {
        column_definition.* = try reader.readStructEndian(ExcelColumnDefinition, .big);
    }

    // Read the page definitions
    const page_count = header.header.page_count;
    header.page_definitions = try header.allocator.alloc(ExcelPageDefinition, page_count);
    errdefer header.allocator.free(header.page_definitions);
    for (header.page_definitions) |*page_definition| {
        page_definition.* = try reader.readStructEndian(ExcelPageDefinition, .big);
    }

    // Read the languages
    const language_count = header.header.language_count;
    header.languages = try header.allocator.alloc(Language, language_count);
    errdefer header.allocator.free(header.languages);
    for (header.languages) |*language| {
        const byte_value = try reader.readByte();
        language.* = @enumFromInt(byte_value);

        // weird, but needed - another value, string length?
        try reader.skipBytes(1, .{});
    }
}
