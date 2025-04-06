const std = @import("std");
const Allocator = std.mem.Allocator;

const game = @import("game.zig");
const GameVersion = game.GameVersion;
const Language = game.Language;
const Platform = game.Platform;
const Pack = game.sqpack.Pack;

const Calyx = @This();

const VersionFile = "ffxivgame.ver";
const SqPackRepoPath = "sqpack";

allocator: Allocator,
game_path: []const u8,
platform: Platform,
language: Language,
version: GameVersion,
pack: *Pack,

/// Initializes the Calyx module.
///
/// Basic validation and loading is performed but no game data is loaded.
///
/// The caller is responsible for providing a valid `Allocator` instance.
///
/// The `game_path` should point to the root directory of the game installation.
/// It should contain the `ffxivgame.ver` file and the `sqpack` directory.
///
/// The `platform` should be the platform the game files are from.
///
/// The `language` should be the preffered language when reading localized data.
///
/// Returns a pointer to the initialized `Calyx` instance.
/// The caller is responsible for freeing the instance using `deinit`.
pub fn init(allocator: Allocator, game_path: []const u8, platform: Platform, language: Language) !*Calyx {
    std.log.info("Initializing Calyx with game path: {s}...", .{game_path});

    const calyx = try allocator.create(Calyx);
    errdefer allocator.destroy(calyx);

    // We need to clone the game path
    const cloned_game_path = try allocator.dupe(u8, game_path);
    errdefer allocator.free(cloned_game_path);

    // Temp stack allocator for path building
    var sfb = std.heap.stackFallback(2048, allocator);
    const sfa = sfb.get();

    // Load the game version
    const game_version_file_path = try std.fs.path.join(sfa, &.{ cloned_game_path, VersionFile });
    defer sfa.free(game_version_file_path);
    const game_version = GameVersion.parseFromFilePath(game_version_file_path) catch GameVersion.UnknownVersion;

    // Setup the sqpack
    const sqpack_repo_path = try std.fs.path.join(sfa, &.{ cloned_game_path, SqPackRepoPath });
    defer sfa.free(sqpack_repo_path);
    var sqpack_dir = try std.fs.openDirAbsolute(sqpack_repo_path, .{ .access_sub_paths = false });
    sqpack_dir.close();

    const pack = try Pack.init(
        allocator,
        platform,
        game_version,
        sqpack_repo_path,
    );
    errdefer pack.deinit();

    calyx.* = .{
        .allocator = allocator,
        .game_path = cloned_game_path,
        .platform = platform,
        .language = language,
        .version = game_version,
        .pack = pack,
    };

    std.log.info("Calyx initialized with game version: {s}", .{calyx.version.str});

    return calyx;
}

/// Deinitializes the `Calyx` instance.
///
/// The caller should not use the `Calyx` instance after this function is called.
pub fn deinit(calyx: *Calyx) void {
    calyx.pack.deinit();
    calyx.allocator.free(calyx.game_path);
    calyx.allocator.destroy(calyx);
}
