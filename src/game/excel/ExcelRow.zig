const std = @import("std");
const Allocator = std.mem.Allocator;

const native_types = @import("native_types.zig");
const ExcelColumnDefinition = native_types.ExcelColumnDefinition;
const ExcelColumnType = native_types.ExcelColumnType;

const ExcelColumnValue = @import("excel_column_value.zig").ExcelColumnValue;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelRow = @This();

columns: []ExcelColumnValue,

pub fn populate(
    allocator: Allocator,
    row_offset: u64,
    column_start: u64,
    extra_offset: u64,
    column_definitions: []native_types.ExcelColumnDefinition,
    bsr: *BufferedStreamReader,
) !ExcelRow {
    _ = row_offset;

    const columns = try allocator.alloc(ExcelColumnValue, column_definitions.len);
    errdefer allocator.free(columns);

    for (column_definitions, 0..) |*column_definition, i| {
        const column_offset = column_start + column_definition.offset;
        try bsr.seekTo(column_offset);
        columns[i] = try readColumnValue(allocator, column_definition.column_type, extra_offset, bsr);
    }

    return ExcelRow{
        .columns = columns,
    };
}

pub fn destroy(row: *ExcelRow, allocator: Allocator) void {
    for (row.columns) |column| {
        switch (column) {
            .string => |s| {
                allocator.free(s);
            },
            else => {},
        }
    }

    allocator.free(row.columns);
}

fn readColumnValue(
    allocator: Allocator,
    column_type: ExcelColumnType,
    extra_offset: u64,
    bsr: *BufferedStreamReader,
) !ExcelColumnValue {
    switch (column_type) {
        .string => {
            const string_offset = try bsr.reader().readInt(u32, .big);
            const absolute_offset = extra_offset + string_offset;
            try bsr.seekTo(absolute_offset);
            const str = try bsr.reader().readUntilDelimiterOrEofAlloc(allocator, '\x00', 2048);
            return ExcelColumnValue{ .string = str.? };
        },

        .bool => {
            const value = try bsr.reader().readByte() != 0;
            return ExcelColumnValue{ .bool = value };
        },
        .i8 => {
            const value = try bsr.reader().readInt(i8, .big);
            return ExcelColumnValue{ .i8 = value };
        },
        .u8 => {
            const value = try bsr.reader().readInt(u8, .big);
            return ExcelColumnValue{ .u8 = value };
        },
        .i16 => {
            const value = try bsr.reader().readInt(i16, .big);
            return ExcelColumnValue{ .i16 = value };
        },
        .u16 => {
            const value = try bsr.reader().readInt(u16, .big);
            return ExcelColumnValue{ .u16 = value };
        },
        .i32 => {
            const value = try bsr.reader().readInt(i32, .big);
            return ExcelColumnValue{ .i32 = value };
        },
        .u32 => {
            const value = try bsr.reader().readInt(u32, .big);
            return ExcelColumnValue{ .u32 = value };
        },
        .f32 => {
            const bits = try bsr.reader().readInt(u32, .big);
            return ExcelColumnValue{ .f32 = @bitCast(bits) };
        },
        .i64 => {
            const value = try bsr.reader().readInt(i64, .big);
            return ExcelColumnValue{ .i64 = value };
        },
        .u64 => {
            const value = try bsr.reader().readInt(u64, .big);
            return ExcelColumnValue{ .u64 = value };
        },
        .packed_bool0 => {
            const value = try bsr.reader().readByte() & 1 != 0;
            return ExcelColumnValue{ .packed_bool0 = value };
        },
        .packed_bool1 => {
            const value = try bsr.reader().readByte() & 2 != 0;
            return ExcelColumnValue{ .packed_bool1 = value };
        },
        .packed_bool2 => {
            const value = try bsr.reader().readByte() & 4 != 0;
            return ExcelColumnValue{ .packed_bool2 = value };
        },
        .packed_bool3 => {
            const value = try bsr.reader().readByte() & 8 != 0;
            return ExcelColumnValue{ .packed_bool3 = value };
        },
        .packed_bool4 => {
            const value = try bsr.reader().readByte() & 16 != 0;
            return ExcelColumnValue{ .packed_bool4 = value };
        },
        .packed_bool5 => {
            const value = try bsr.reader().readByte() & 32 != 0;
            return ExcelColumnValue{ .packed_bool5 = value };
        },
        .packed_bool6 => {
            const value = try bsr.reader().readByte() & 64 != 0;
            return ExcelColumnValue{ .packed_bool6 = value };
        },
        .packed_bool7 => {
            const value = try bsr.reader().readByte() & 128 != 0;
            return ExcelColumnValue{ .packed_bool7 = value };
        },
    }

    return error.InvalidColumnType;
}
