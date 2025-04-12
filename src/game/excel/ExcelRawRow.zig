const std = @import("std");

const meta = @import("../../core/meta.zig");

const native_types = @import("native_types.zig");
const ExcelColumnDefinition = native_types.ExcelColumnDefinition;
const ExcelSheetType = native_types.ExcelSheetType;

const ExcelRawRow = @This();

sheet_type: ExcelSheetType,
data: []const u8,
row_count: u16,
fixed_size: usize,
column_definitions: []ExcelColumnDefinition,

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
pub fn getRowColumnValue(row: *const ExcelRawRow, comptime T: type, column_id: u16) !T {
    if (row.sheet_type != .default) {
        @branchHint(.unlikely);
        return error.InvalidSheetType; // Likely need to use getSubRowColumnValue instead
    }

    if (column_id >= row.column_definitions.len) {
        @branchHint(.unlikely);
        return error.InvalidColumnId;
    }

    const column_def = row.column_definitions[column_id];

    return unpackColumn(row, T, 0, column_def);
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
pub fn getSubRowColumnValue(row: *const ExcelRawRow, comptime T: type, subrow_id: u16, column_id: u16) !T {
    if (row.sheet_type != .sub_rows) {
        @branchHint(.unlikely);
        return error.InvalidSheetType; // Likely need to use getRowColumnValue instead
    }

    if (column_id >= row.column_definitions.len) {
        @branchHint(.unlikely);
        return error.InvalidColumnId;
    }

    if (subrow_id >= row.row_count) {
        @branchHint(.unlikely);
        return error.RowNotFound;
    }

    const subrow_offset = subrow_id * row.fixed_size + 2 * (subrow_id + 1);
    const column_def = row.column_definitions[column_id];

    return unpackColumn(row, T, subrow_offset, column_def);
}

fn unpackColumn(row: *const ExcelRawRow, comptime T: type, base_offset: usize, column_def: ExcelColumnDefinition) !T {
    if (meta.typeId(T) != column_def.column_type.typeId()) {
        @branchHint(.unlikely);
        return error.ColumnTypeMismatch;
    }

    var buffer = std.io.fixedBufferStream(row.data);
    try buffer.seekTo(base_offset + column_def.offset);

    return switch (T) {
        u8, u16, u32, u64, i8, i16, i32, i64 => try buffer.reader().readInt(T, .big),
        f32 => @as(f32, @bitCast(try buffer.reader().readInt(u32, .big))),
        bool => switch (column_def.column_type) {
            .bool => try buffer.reader().readByte() != 0,
            else => |x| (try x.packedBoolMask() & try buffer.reader().readByte()) != 0,
        },
        []const u8 => blk: {
            const str_offset = base_offset + row.fixed_size + try buffer.reader().readInt(u32, .big);
            const str_aligned = row.data[str_offset..];
            const str_len = std.mem.indexOfScalar(u8, str_aligned, 0);
            if (str_len == null) {
                @branchHint(.cold);
                return error.InvalidString;
            }
            const str = str_aligned[0..str_len.?];
            break :blk str;
        },
        else => error.InvalidType,
    };
}
