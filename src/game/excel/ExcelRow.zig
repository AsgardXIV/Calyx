const std = @import("std");
const Allocator = std.mem.Allocator;

const ExcelColumnType = @import("native_types.zig").ExcelColumnType;
const ExcelColumnValue = @import("excel_column_value.zig").ExcelColumnValue;
const ExcelSheet = @import("ExcelSheet.zig");

const native_types = @import("native_types.zig");
const ExcelDataRowPreamble = native_types.ExcelDataRowPreamble;

const BufferedStreamReader = @import("../../core/io/buffered_stream_reader.zig").BufferedStreamReader;

const ExcelRow = @This();

row_id: u32,
columns: []ExcelColumnValue,

pub fn populate(
    allocator: Allocator,
    row_id: u32,
    row_offset: u32,
    column_definitions: []native_types.ExcelColumnDefinition,
    bsr: *BufferedStreamReader,
) !ExcelRow {
    try bsr.seekTo(row_offset);

    const preamble = try bsr.reader().readStructEndian(ExcelDataRowPreamble, .big);
    _ = preamble;

    const data_offset = try bsr.getPos();

    const columns = try allocator.alloc(ExcelColumnValue, column_definitions.len);
    errdefer allocator.free(columns);

    for (column_definitions, 0..) |*column_definition, i| {
        const column_offset = data_offset + column_definition.offset;
        try bsr.seekTo(column_offset);
        columns[i] = try readColumnValue(allocator, column_definition.column_type, bsr);
    }

    return ExcelRow{
        .row_id = row_id,
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
    bsr: *BufferedStreamReader,
) !ExcelColumnValue {
    switch (column_type) {
        .string => {
            return ExcelColumnValue{ .string = "" };
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
    _ = allocator;
    return error.InvalidColumnType;
}
