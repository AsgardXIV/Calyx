//! Calyx is a Zig library for interacting with game files from Final Fantasy XIV.
//! It aims to offer features and functionality available in other languages to interact with FFXIV to Zig developers.
//!
//! Typically you want to use the `GameData` struct to access the game files.
//! See `GameData.init` for more details on how to initialize it.

const std = @import("std");

pub const core = @import("core.zig");
pub const game = @import("game.zig");

pub const GameData = @import("GameData.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
