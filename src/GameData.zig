const std = @import("std");
const Allocator = std.mem.Allocator;

const game = @import("game.zig");
const GameVersion = game.GameVersion;
const Language = game.Language;
const Platform = game.Platform;
const Pack = game.sqpack.Pack;
const ExcelModule = game.excel.ExcelModule;
const ExcelSheet = game.excel.ExcelSheet;

const VersionFile = "ffxivgame.ver";
const SqPackRepoPath = "sqpack";
const GameEnvVar = "FFXIV_GAME_PATH";

const GameData = @This();

pub const Options = struct {
    /// The root directory of the game data.
    /// It should contain the `ffxivgame.ver` file and the `sqpack` directory.
    /// If the value is `null`, it will attempt to read the `FFXIV_GAME_PATH` environment variable.
    path: ?[]const u8 = null,

    /// The platform from which the game data was provided.
    platform: Platform = .win32,

    /// The language localized data is provided in.
    language: Language = .english,
};

allocator: Allocator,
path: []const u8,
platform: Platform,
language: Language,
version: GameVersion,
pack: *Pack,
excel: *ExcelModule,

/// Initializes the `GameData` instance.
/// Basic validation is performed but no game data is loaded.
///
/// `allocator` is the allocator used for memory management.
/// `options` can be used to specify additional options and customization.
///
/// Returns a pointer to the initialized `GameData` instance.
/// The caller is responsible for freeing the instance using `deinit`.
pub fn init(allocator: Allocator, options: Options) !*GameData {
    const data = try allocator.create(GameData);
    errdefer allocator.destroy(data);

    // We need to clone the game path
    const cloned_game_path = blk: {
        if (options.path) |path| {
            break :blk try allocator.dupe(u8, path);
        } else {
            break :blk try std.process.getEnvVarOwned(allocator, GameEnvVar);
        }
    };
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
    try std.fs.accessAbsolute(sqpack_repo_path, .{}); // Sanity check

    const pack = try Pack.init(
        allocator,
        options.platform,
        game_version,
        sqpack_repo_path,
    );
    errdefer pack.deinit();

    // Setup the excel module
    const excel_module = try ExcelModule.init(
        allocator,
        options.language,
        pack,
    );
    errdefer excel_module.deinit();

    // Populate the instance
    data.* = .{
        .allocator = allocator,
        .path = cloned_game_path,
        .platform = options.platform,
        .language = options.language,
        .version = game_version,
        .pack = pack,
        .excel = excel_module,
    };

    return data;
}

/// Deinitializes the `GameData` instance.
/// The caller should not use the instance after this function is called.
pub fn deinit(data: *GameData) void {
    data.excel.deinit();
    data.pack.deinit();
    data.allocator.free(data.path);
    data.allocator.destroy(data);
}

/// Loads the raw file contents for a given path from the pack.
///
/// `allocator` is the allocator used for memory management.
/// `path` should be a string representing the path to the file.
///
/// Returns the file contents as a byte slice or an error if the file is not found or an error occurs.
/// Caller is responsible for freeing the returned slice.
pub fn getFileContents(data: *GameData, allocator: Allocator, path: []const u8) ![]const u8 {
    return data.pack.getFileContents(allocator, path);
}

/// Loads a file from the pack and deserializes it into the given type.
///
/// The type `FileType` must implement the following methods:
/// - `pub fn init(allocator: Allocator, stream: *std.io.FixedBufferStream([]const u8)) !*FileType`
/// - `pub fn deinit(self: *FileType) void`
///
/// init must allocate the instance using the provided allocator and initialize it from the stream.
/// The instance must not access the stream after initialization.
/// deinit must free the instance using the allocator provided in init.
///
/// The caller owns the returned instance must free it using `FileType.deinit`.
pub fn getTypedFile(data: *GameData, allocator: Allocator, comptime FileType: type, path: []const u8) !*FileType {
    return data.pack.getTypedFile(allocator, FileType, path);
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
pub fn getSheet(data: *GameData, sheet_name: []const u8) !*ExcelSheet {
    return data.excel.getSheet(sheet_name);
}
