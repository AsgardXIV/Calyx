const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelHeaderHeader = native_types.ExcelHeaderHeader;
const ExcelColumnDefinition = native_types.ExcelColumnDefinition;
const ExcelPageDefinition = native_types.ExcelPageDefinition;

const Language = @import("../language.zig").Language;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelHeader = @This();

allocator: Allocator,
header: ExcelHeaderHeader,
column_definitions: []ExcelColumnDefinition,
page_definitions: []ExcelPageDefinition,
languages: []Language,

pub fn init(allocator: Allocator, bsr: *BufferedStreamReader) !*ExcelHeader {
    const header = try allocator.create(ExcelHeader);
    errdefer allocator.destroy(header);

    header.* = .{
        .allocator = allocator,
        .header = undefined,
        .column_definitions = undefined,
        .page_definitions = undefined,
        .languages = undefined,
    };

    try header.populate(bsr);

    return header;
}

pub fn deinit(header: *ExcelHeader) void {
    header.allocator.free(header.column_definitions);
    header.allocator.free(header.page_definitions);
    header.allocator.free(header.languages);

    header.allocator.destroy(header);
}

fn populate(header: *ExcelHeader, bsr: *BufferedStreamReader) !void {
    const reader = bsr.reader();

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
        language.* = try reader.readEnum(Language, .big);
    }
}
