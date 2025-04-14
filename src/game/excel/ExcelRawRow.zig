const std = @import("std");

const native_types = @import("native_types.zig");
const ExcelDataRowPreamble = native_types.ExcelDataRowPreamble;
const ExcelColumnDefinition = native_types.ExcelColumnDefinition;
const ExcelSheet = @import("ExcelSheet.zig");
const ExcelRawColumnValue = @import("excel_raw_column_value.zig").ExcelRawColumnValue;

const ExcelRawRow = @This();

sheet: *ExcelSheet,
preamble: ExcelDataRowPreamble,
data: []const u8,

/// Gets the value of a column in the row.
///
/// This function is used when the row is of type `ExcelSheetType.default`. See `ExcelRawRow.getSubRowColumnValue` for `ExcelSheetType.sub_rows` sheets.
///
/// `T` type must match the column type defined in the header otherwise an error is returned.
///
/// `column_id` is the index of the column in the header. An error is returned if if is out of bounds.
///
/// No heap allocations are performed in this function.
/// The returned data is valid until the sheet is deinitialized.
pub fn getRowColumnValue(row: *const ExcelRawRow, column_id: u16) !ExcelRawColumnValue {
    if (row.sheet.excel_header.header.sheet_type != .default) {
        return error.InvalidSheetType; // Likely need to use getSubRowColumnValue instead
    }

    if (column_id >= row.sheet.excel_header.column_definitions.len) {
        return error.InvalidColumnId;
    }

    const column_def = row.sheet.excel_header.column_definitions[column_id];

    return unpackColumn(row, 0, column_def);
}

/// Gets the value of a column in a subrow.
///
/// This function is used when the row is of type `ExcelSheetType.sub_rows`. See `ExcelRawRow.getRowColumnValue` for `ExcelSheetType.default` sheets.
///
/// The `T` type must match the column type defined in the header otherwise an error is returned.
///
/// `subrow_id` is the index of the subrow in the row. An error is returned if it is out of bounds.
///
/// `column_id` is the index of the column in the header. An error is returned if it is out of bounds.
///
/// No heap allocations are performed in this function.
/// The returned data is valid until the sheet is deinitialized.
pub fn getSubRowColumnValue(row: *const ExcelRawRow, subrow_id: u16, column_id: u16) !ExcelRawColumnValue {
    if (row.sheet.excel_header.header.sheet_type != .sub_rows) {
        return error.InvalidSheetType; // Likely need to use getSubRowColumnValue instead
    }

    if (column_id >= row.sheet.excel_header.column_definitions.len) {
        return error.InvalidColumnId;
    }

    if (subrow_id >= row.preamble.row_count) {
        return error.RowNotFound;
    }

    const subrow_offset = subrow_id * row.sheet.excel_header.header.data_offset + 2 * (subrow_id + 1);
    const column_def = row.sheet.excel_header.column_definitions[column_id];

    return unpackColumn(row, subrow_offset, column_def);
}

fn unpackColumn(row: *const ExcelRawRow, base_offset: usize, column_def: ExcelColumnDefinition) !ExcelRawColumnValue {
    var buffer = std.io.fixedBufferStream(row.data);
    try buffer.seekTo(base_offset + column_def.offset);

    return switch (column_def.column_type) {
        .string => blk: {
            const str_offset = base_offset + row.sheet.excel_header.header.data_offset + try buffer.reader().readInt(u32, .big);
            const str_aligned = row.data[str_offset..];
            const str_len = std.mem.indexOfScalar(u8, str_aligned, 0);
            if (str_len == null) {
                return error.InvalidString;
            }
            const str = str_aligned[0..str_len.?];
            break :blk .{
                .string = str,
            };
        },
        .bool => .{ .bool = try buffer.reader().readByte() != 0 },

        .i8 => .{ .i8 = try buffer.reader().readInt(i8, .big) },
        .u8 => .{ .u8 = try buffer.reader().readInt(u8, .big) },
        .i16 => .{ .i16 = try buffer.reader().readInt(i16, .big) },
        .u16 => .{ .u16 = try buffer.reader().readInt(u16, .big) },
        .i32 => .{ .i32 = try buffer.reader().readInt(i32, .big) },
        .u32 => .{ .u32 = try buffer.reader().readInt(u32, .big) },

        .f32 => .{ .f32 = @bitCast(try buffer.reader().readInt(u32, .big)) },

        .i64 => .{ .i64 = try buffer.reader().readInt(i64, .big) },
        .u64 => .{ .u64 = try buffer.reader().readInt(u64, .big) },

        .packed_bool0,
        .packed_bool1,
        .packed_bool2,
        .packed_bool3,
        .packed_bool4,
        .packed_bool5,
        .packed_bool6,
        .packed_bool7,
        => .{ .bool = try buffer.reader().readByte() & try column_def.column_type.packedBoolMask() != 0 },
    };
}
