# Pallid-Framework

A library for Project Zomboid Build 42 mod development: a widget toolkit, drawing and
animation helpers, gameplay helpers for traits, professions and custom moodles, a
client/server message layer, and shared utilities exposed through the single
`Pallid` global.

## Requirements

- Project Zomboid Build 42.21.0 or newer.
- Mods using the framework must declare `Pallid-Framework` (`pallid-framework`) as a dependency.

## Installation

Copy the `pallid-framework` folder into your Zomboid `mods` directory and enable
**Pallid Framework** in the in-game mod list.

## Usage

Lua modules are loaded by the game from `42/media/lua/{client,server,shared}/`.
Public API is accessed through the `Pallid` table; `Pallid.log` and `Pallid.error`
are the shared logging helpers.

## Networking

`Pallid.Net` is the shared client/server message layer. Register an action once
and receive a validated payload; the layer owns the native command listener,
rate limiting, payload checks and optional replay protection.

```lua
Pallid.Net.onServer("Shop_buy", {
    limit  = { max = 5, window = 1000, },
    schema = { id = "string", count = "number", },
}, function(player, payload)
    Pallid.Net.send(player, "Shop_result", { ok = true, })
end)

Pallid.Net.onClient("Shop_result", function(payload) end)
Pallid.Net.sendToServer("Shop_buy", { id = "apple", count = 1, })
```

Send functions return `ok, err`. Server actions get a conservative default rate
limit when `limit` is omitted, plus a global per-player limit; `limit = false`
opts out of the per-action bucket. Rate limits, capabilities and `dedup` replay
protection are server-only options. Payloads are checked for unsupported types,
oversized strings, cycles, depth and non-finite numbers. See
[docs/net.md](docs/net.md).

## Moodles

Moodles are server-authoritative by default. Only definitions registered with
`clientWritable = true` accept client `setValue`/`Moodles_set` updates; use that
for visual or derived moodles. Gameplay-relevant moodles should stay
server-owned and be computed on the server. See
[docs/gameplay-moodles.md](docs/gameplay-moodles.md).

## Documentation

Full API and usage documentation lives in the documentation index:
[docs/README.md](docs/README.md).

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).
