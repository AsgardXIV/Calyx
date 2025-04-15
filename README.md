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
 
## Alternativies
Not using Zig?
* C#
  * [Lumina](https://github.com/NotAdam/Lumina)
  * [SaintCoinach](https://github.com/xivapi/SaintCoinach)
  * [xivModdingFramework](https://github.com/TexTools/xivModdingFramework)
* Rust
  * [Physis](https://github.com/redstrate/Physis)
 
## Acknowledgements
Calyx is frequently based on the work done by other projects, particularly those listed in the `Alternatives` section. 
