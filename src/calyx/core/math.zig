pub fn padTo(value: anytype, padding: @TypeOf(value)) @TypeOf(value) {
    const type_info = @typeInfo(@TypeOf(value));
    comptime if (type_info != .int and type_info != .comptime_int) {
        @compileError("padTo only works with integer types");
    };

    const remainder = value % padding;
    if (remainder == 0) {
        return value;
    } else {
        return value + (padding - remainder);
    }
}
