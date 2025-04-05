const std = @import("std");

pub const core = @import("core.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
