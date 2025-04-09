const std = @import("std");
const Allocator = std.mem.Allocator;

const game = @import("game.zig");
const GameVersion = game.GameVersion;
const Language = game.Language;
const Platform = game.Platform;
const Pack = game.sqpack.Pack;

const ExcelSystem = @import("game/excel/ExcelSystem.zig");
const ExcelSheet = @import("game/excel/ExcelSheet.zig");

const BufferedStreamReader = @import("core/io/buffered_stream_reader.zig").BufferedStreamReader;

const Calyx = @This();

const VersionFile = "ffxivgame.ver";
const SqPackRepoPath = "sqpack";

allocator: Allocator,
game_path: []const u8,
platform: Platform,
language: Language,
version: GameVersion,
pack: *Pack,
excel_system: *ExcelSystem,

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

    // Setup the excel system
    const excel_system = try ExcelSystem.init(
        allocator,
        language,
        pack,
    );
    errdefer excel_system.deinit();

    calyx.* = .{
        .allocator = allocator,
        .game_path = cloned_game_path,
        .platform = platform,
        .language = language,
        .version = game_version,
        .pack = pack,
        .excel_system = excel_system,
    };

    std.log.info("Calyx initialized with game version: {s}", .{calyx.version.str});

    return calyx;
}

/// Deinitializes the `Calyx` instance.
///
/// The caller should not use the `Calyx` instance after this function is called.
pub fn deinit(calyx: *Calyx) void {
    calyx.excel_system.deinit();
    calyx.pack.deinit();
    calyx.allocator.free(calyx.game_path);
    calyx.allocator.destroy(calyx);
}

/// Loads the raw file contents for a given path from the pack.
///
/// Caller must provide an allocator to manage memory for the file contents.
///
/// The `path` should be a string representing the path to the file.
///
/// Returns the file contents as a byte slice or an error if the file is not found or an error occurs.
/// Caller is responsible for freeing the returned slice.
pub fn getFileContents(calyx: *Calyx, allocator: Allocator, path: []const u8) ![]const u8 {
    return calyx.pack.getFileContents(allocator, path);
}

/// Loads a file from the pack and deserializes it into the given type.
///
/// The type `FileType` must implement the following methods:
/// - `pub fn init(allocator: Allocator, stream: *BufferedStreamReader) !*FileType`
/// - `pub fn deinit(self: *FileType) void`
///
/// init must allocate the instance using the provided allocator and initialize it from the stream.
/// The instance must not access the stream after initialization.
/// deinit must free the instance using the allocator provided in init.
///
/// The caller owns the returned instance must free it using `FileType.deinit`.
pub fn getTypedFile(calyx: *Calyx, allocator: Allocator, comptime FileType: type, path: []const u8) !*FileType {
    return calyx.pack.getTypedFile(allocator, FileType, path);
}

/// Get an excel sheet by its name.
///
/// If the sheet is already cached, it will return the cached version.
/// If the sheet is not cached, it will load it and return it.
/// If the sheet is not found, it will return an error.
///
/// It will always attempt to return the sheet with the preferred language.
/// If the sheet is not found in the preferred language, it will return the sheet with the None language.
/// If the sheet is not found in any language, it will return an error.
///
/// The caller is not responsible for freeing the returned sheet.
pub fn getSheet(calyx: *Calyx, sheet_name: []const u8) !*ExcelSheet {
    return calyx.excel_system.getSheet(sheet_name);
}
