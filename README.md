# Pallid-Framework

A library for Project Zomboid Build 42 mod development: a widget toolkit, drawing and
animation helpers, and shared utilities exposed through the single `Pallid` global.

## Requirements

- Project Zomboid Build 42.21.0 or newer.
- Mods using the framework must declare `Pallid-Framework` (`pallid-framework`) as a dependency.

## Installation

Copy the `pallid-framework` folder into your Zomboid `mods` directory and enable
**Pallid Framework** in the in-game mod list.

## Structure

- `42/` — Build 42 files: Lua modules, UI assets, and translations (`EN`, `RU`).
- `common/` — placeholder for older Build 42 versions.

## Usage

Lua modules are loaded by the game from `42/media/lua/{client,server,shared}/`.
Public API is accessed through the `Pallid` table; `Pallid.log` and `Pallid.error`
are the shared logging helpers.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
