const std = @import("std");

pub const core = @import("core.zig");
pub const game = @import("game.zig");

pub const GameData = @import("GameData.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
