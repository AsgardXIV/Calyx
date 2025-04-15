# Calyx

A Zig library for interacting with game files from Final Fantasy XIV. 
<br/>It aims to offer features and functionality available in other languages to interact with FFXIV to Zig developers.

## State of the project
Calyx is still very early in development and the API surface is not stable. Contributions are appreciated.

## Current Features
* SqPack
  * Mounting SqPack
  * Discovering and accessing repositories, categories and chunks
  * Index1 and Index2 exploration
  * Game path parsing and hashing
  * Retrieving files via game path or index hash
     * Standard, Texture and Model
* Excel
  * Load the root.exl and lookup sheets via id
  * Load sheets
  * Retrieve or iterate rows
  * Retrieve column data

## Future Plans
* Type safe Excel access (using EXDSchema or SaintCoinach defs or similar)
* Game file format support (Models, Textures, Skeletons etc) both reading and writing

## Using the Library
1. Add Calyx to your build.zig.zon
```
zig fetch --save git+https://github.com/AsgardXIV/Calyx.git
```

2. Add the dependency to your project, for example:
```zig
const calyx_dependency = b.dependency("calyx", .{
  .target = target,
  .optimize = optimize,
});

exe_mod.addImport("calyx", calyx_dependency.module("calyx"));
```

3. Use the library
```zig
 // Init Calyx
const calyx = @import("calyx");
const game = try calyx.GameData.init(allocator, .{});
defer game.deinit();

// Read a game file
const swine_head_model = try game.getFileContents(allocator, "chara/equipment/e6023/model/c0101e6023_met.mdl");
defer allocator.free(swine_head_model);
try std.io.getStdOut().writer().print("Swine Head model length: {d} bytes\n", .{swine_head_model.len});

// Read from Excel
const sheet = try game.getSheet("Item");
const wind_up_raha = try sheet.getRow(23992);
const wind_up_raha_name = try wind_up_raha.getRowColumnValue(9);
try std.io.getStdOut().writer().print("Item Name: {s}\n", .{wind_up_raha_name.string});
```

## Developing Locally
Some development requires a locally installed copy of FFXIV. You should set the `FFXIV_GAME_PATH` environment variable so Calyx can discover the location.

1. Running the sample: `zig build sample`
2. Running the unit tests: `zig build test`
3. Running the integration tests: `zig build integrationTest`
4. Generating the docs: `zig build docs`

## Alternatives
Not using Zig?
* C#
  * [Lumina](https://github.com/NotAdam/Lumina)
  * [SaintCoinach](https://github.com/xivapi/SaintCoinach)
  * [xivModdingFramework](https://github.com/TexTools/xivModdingFramework)
* Rust
  * [Physis](https://github.com/redstrate/Physis)
 
## Acknowledgements
Calyx is frequently based on the work done by other projects, particularly those listed in the `Alternatives` section. 
