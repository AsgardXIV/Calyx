const std = @import("std");

pub const common = @import("common/root.zig");
pub const core = @import("core/root.zig");
pub const sqpack = @import("sqpack/root.zig");

pub usingnamespace @import("game_data.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
