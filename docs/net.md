# Pallid.Net

`Pallid.Net` is a client/server message layer for Pallid mods. It wraps the native Lua command transport so a mod registers a named action once instead of filtering `Events.OnClientCommand` and `Events.OnServerCommand` itself.

`Pallid.Net` lives in shared Lua. If your mod registers actions while its own shared files load, run `require "pallid/net/core"` first; the framework does not load it for you. Log output is described in [logger](logger.md).

## Protocol

Every message is one native command with module `Pallid_Net` and command `msg`. The native arguments table is the envelope. It has three required fields — `a` (string, action name), `p` (any codec-valid payload) and `v` (number, protocol version `1`) — and one optional field, `n` (number, dedup nonce).

**Side:** shared

### Notes
- A message whose `v` is not the number `1` is dropped and logged through `Pallid.warn`, at most once every 5 seconds. The peer is not kicked or disconnected.
- An envelope with any key other than `a`, `p`, `v` or `n` is dropped and logged as a malformed envelope. The offending key is not logged because it is sender-controlled.
- A non-table envelope, or an envelope whose `a` is not a string, is dropped silently.
- `n` is a random nonce sent by every client-to-server message. It is only checked when the action opted into `dedup`.
- The envelope carries no sender field. On the server the sender is taken from the command event, never from `p`.
- `nil` cannot be sent as `p`: the native serializer omits the key, so the receiver cannot tell it apart from a missing payload. Send an empty table instead.

## Pallid.Net.onServer

Registers a server-side handler for one action. The handler receives `(player, payload)` and runs on the server, or in-process in singleplayer.

**Side:** shared

### Parameters
- action (string) - Non-empty action name, by convention `Owner_action`.
- options (table|nil) - Optional table holding `limit`, `schema`, `capability` and/or `dedup`. May be omitted when the handler is passed as the second argument.
- handler (function) - Called as `handler(player, payload)`. `player` is the sending `IsoPlayer` taken from the command event.

### Returns
- boolean - `true` when the registration was accepted.
- string|nil - Failure reason on rejection: `action required`, `handler required`, `duplicate action`, or the option validation reason.

### Example
```lua
Pallid.Net.onServer("Shop_buy", {
    limit  = { max = 5, window = 1000, },
    schema = { id = "string", count = { type = "number", min = 1, max = 10, }, },
}, function(player, payload)
    Pallid.Net.send(player, "Shop_result", { id = payload.id, count = payload.count, })
end)
```

### Notes
- A duplicate action on the same side is rejected and logged with `Pallid.error`; the first handler stays in place.
- An unknown option key rejects the registration, as does passing `limit`, `capability` or `dedup` to [onClient](#pallidnetonclient).
- When `limit` is omitted the handler gets the conservative default `{ max = 10, window = 1000 }`. Pass `limit = false` to opt out of the per-action limit; the global per-player limit still applies.
- `dedup = true` enables replay protection for this action. Every client message already carries the `n` nonce.
- Registration is allowed on every side, because the server Lua directory also loads on a multiplayer client. Such a client-side registration never fires in multiplayer: the server listener returns early when `isClient() and not isServer()`.
- A handler error is caught with `pcall`, logged with `Pallid.error`, and does not stop the dispatcher or other handlers. The send function has already returned by then.

## Pallid.Net.onClient

Registers a client-side handler for one action. The handler receives `(payload)` and runs on the client, or in-process in singleplayer.

**Side:** shared

### Parameters
- action (string) - Non-empty action name, by convention `Owner_action`.
- options (table|nil) - Optional table holding `schema` only.
- handler (function) - Called as `handler(payload)`.

### Returns
- boolean - `true` when the registration was accepted.
- string|nil - Failure reason on rejection: `action required`, `handler required`, `duplicate action`, or the option validation reason.

### Example
```lua
Pallid.Net.onClient("Shop_result", function(payload)
    Pallid.log("shop result", payload.id, payload.count)
end)
```

### Notes
- `limit`, `capability` and `dedup` are server-only and are rejected here instead of being ignored.
- Registering the same action twice on the client side is rejected and logged with `Pallid.error`.

## Pallid.Net.sendToServer

Sends one message from the local client to the server. The native packet is sent as the primary local player (`getPlayer()`).

**Side:** client

### Parameters
- action (string) - Non-empty action name matching a registered server handler.
- payload (any) - Codec-valid value. Use an empty table when the action carries no data.

### Returns
- boolean - `true` when the message was accepted for delivery.
- string|nil - Failure reason: `action must be a non-empty string`, `cannot send to the server from the server`, `no local player`, `local player expected`, `native send failed`, or the codec rejection reason.
### Example
```lua
local ok, reason = Pallid.Net.sendToServer("Shop_buy", { id = "apple", count = 2, })
if not ok then
    Pallid.warn("shop send failed:", reason)
end
```

### Notes
- `true` means accepted, not handled. An unknown action is dropped, only logged in debug mode, and returns `true` unless the global per-player limit already dropped the message.
- In singleplayer the registered server handler is called synchronously through the local dispatch path and the native transport is not used, so the message is never delivered twice. In that path the reason can also be `global rate limited`, `rate limited`, `capability denied`, a dedup reason, or a schema reason.
- Only `getPlayer()` is used. A split-screen secondary player is not supported by this function; framework internals use `_sendToServerAs` when they already hold the correct local player.
- The payload is codec-validated before the native send; a rejected payload is logged through `Pallid.warn`, throttled to one line every 5 seconds.
- Every client-to-server envelope carries a fresh random `n` nonce. It is used only by actions registered with `dedup = true`.

## Pallid.Net.send

Sends one message from the server to one client.

**Side:** server

### Parameters
- player (IsoPlayer) - Target player. It is used only as the transport target and is not passed to the client handler.
- action (string) - Non-empty action name matching a registered client handler.
- payload (any) - Codec-valid value. Use an empty table when the action carries no data.

### Returns
- boolean - `true` when the message was accepted for delivery.
- string|nil - Failure reason: `not authority`, `action must be a non-empty string`, `IsoPlayer expected`, `native send failed`, or the codec rejection reason.

### Example
```lua
Pallid.Net.onServer("Shop_buy", function(player, payload)
    Pallid.Net.send(player, "Shop_result", { id = payload.id, })
end)
```

### Notes
- On a multiplayer client this returns `false, "not authority"`.
- In singleplayer the registered client handler is called synchronously and no native packet is sent; the `IsoPlayer` check still runs, so pass a real player such as `getPlayer()`.
- The payload is codec-validated before the native send, but the client-side schema is not applied on this side.

## Pallid.Net.broadcast

Sends one message from the server to every client.

**Side:** server

### Parameters
- action (string) - Non-empty action name matching a registered client handler.
- payload (any) - Codec-valid value. Use an empty table when the action carries no data.

### Returns
- boolean - `true` when the message was accepted for delivery.
- string|nil - Failure reason: `not authority`, `action must be a non-empty string`, `native send failed`, or the codec rejection reason.

### Example
```lua
if Pallid.Net.isAuthority() then
    Pallid.Net.broadcast("Shop_sale", { id = "apple", })
end
```

### Notes
- On a multiplayer client this returns `false, "not authority"`.
- In singleplayer the registered client handler is called exactly once, in-process.

## Pallid.Net.isAuthority

Reports whether this process owns authoritative game state.

**Side:** shared

### Returns
- boolean - `true` when `isServer()` is true or `isClient()` is false.

### Example
```lua
if Pallid.Net.isAuthority() then
    Pallid.Net.broadcast("Shop_sale", { id = "apple", })
end
```

### Notes
- `true` on a dedicated server, on the co-op server process, and in singleplayer, where neither `isServer()` nor `isClient()` is set.
- `false` on every multiplayer client, including the co-op host client, because the server runs in a separate process.

## Pallid.Net.selfTest

Runs the payload codec self-check and reports the result.

**Side:** shared

### Returns
- boolean - `true` when every codec case produced the expected result.
- number - Number of checks that passed.

### Example
```lua
local ok, passed = Pallid.Net.selfTest()
Pallid.log("codec self-test", ok, passed)
```

### Notes
- Manual debugging helper; it is not called during load. Run it from the Lua console while debug mode is enabled.
- Outside debug mode the call returns `false, 0` and writes a warning instead of running the heavy check.
- Failures are logged with `Pallid.error`, success with `Pallid.log`.

## limit

Token-bucket rate limit applied to one server action, per player and per action.

**Side:** server

### Parameters
- max (number) - Bucket capacity and the number of tokens refilled over `window`. Must be finite and at least `1`.
- window (number) - Refill window in milliseconds. Must be finite and at least `1`.

### Example
```lua
Pallid.Net.onServer("Shop_buy", {
    limit = { max = 5, window = 1000, },
}, function(player, payload) end)
```

### Notes
- The bucket starts full with `max` tokens. Each accepted message costs one token. Tokens refill continuously at `max / window` per millisecond, so the bucket never exceeds `max`.
- A message without a token is dropped and the send returns `false, "rate limited"`.
- A rejection logs `rate-limited action <action> for player <onlineID>` through `Pallid.warn`, at most once every 5 seconds.
- When `limit` is omitted, `onServer` applies the conservative default `{ max = 10, window = 1000 }`. Pass `limit = false` to opt out of the per-action limit; the global per-player limit still applies.
- State is keyed by the player's numeric online id and is pruned once per minute from `Events.EveryOneMinute` by comparing stored ids with `getOnlinePlayers()`. Pruning runs only when `isServer()` is true.
- The limit still applies in singleplayer, where the local player's online id is used.
- Rejected by [onClient](#pallidnetonclient) at registration.

## Global rate limit

A second token bucket applies to every client-to-server message before the action is looked up, including unknown actions.

**Side:** server

### Notes
- Capacity and refill are fixed at 50 messages per 1000 milliseconds per player.
- It bounds actions that opted out of their per-action limit and the cost of unknown actions.
- A message over the global limit returns `false, "global rate limited"` and logs `global rate limit reached for player <onlineID>` through `Pallid.warn`, at most once every 5 seconds.
- State is keyed by the numeric online id and pruned together with the per-action limiter state.
- There is no public configuration for this bucket yet.

## schema

Field specification applied to a received payload before the handler runs.

**Side:** shared

### Parameters
- field (string) - Payload key name. Each schema key describes one payload field.
- spec (string|table) - A type string, or a table with `type`, `optional`, `min`, `max` and `maxLength`.

Accepted type strings: `string`, `number`, `boolean`, `table`, `numberMap`. In a spec table, `type` is required, `optional` must be a boolean, `min`/`max` are allowed on `number` only, must be finite, and must not have `min > max`, and `maxLength` is allowed on `string` only, must be a positive integer.

A `numberMap` field must be a table whose values are all numbers. It is used for `Moodles_state.values`.

### Example
```lua
Pallid.Net.onServer("Shop_buy", {
    schema = {
        id    = { type = "string", maxLength = 64, },
        count = { type = "number", min = 1, max = 10, },
        note  = { type = "string", optional = true, },
    },
}, function(player, payload)
    -- payload.count is already clamped to 1..10, extra fields are gone
end)
```

### Notes
- Fields are required unless `optional = true`. A missing required field rejects the message.
- A wrong field type rejects the message with `field '<name>' must be <type>, got <actual>`.
- A numeric field outside `min`/`max` is clamped, not rejected, and the payload table is written in place, so the handler sees the clamped value.
- A string longer than `maxLength` is rejected. The length is measured in UTF-16 code units, while the codec separately enforces the native 32767-byte limit.
- A `numberMap` field is rejected when any value is not a number. The table itself is bounded by the codec key and node limits.
- Fields not listed in the schema are removed from the payload table. The table is owned by the network layer, so this mutation is intended.
- Before an extra field is removed, a known identity field (`onlineID`, `username`, `playerId`, `role`, `steamID`) triggers a throttled spoof warning. The value is never logged.
- A schema requires a table payload. A scalar payload is rejected with `payload must be a table when a schema is set`.
- A `table` field is only type-checked; its contents are not validated by the schema, only by the codec limits. Use `numberMap` when every value must be numeric.
- The schema is applied to received payloads only. Outgoing payloads are checked by the codec alone.
- On the server the order is envelope, version, action lookup, global rate limit, per-action limit, codec, capability, schema, dedup, handler. On the client it is envelope, version, codec, schema, handler.
- An invalid spec rejects the registration at `onServer`/`onClient` time, so a typo cannot silently disable validation.

## capability

Role capability required from the sending player before a server handler runs.

**Side:** server

### Parameters
- capability (Capability) - A game capability value, for example `Capability.AddItem`.

### Example
```lua
Pallid.Net.onServer("Admin_giveItem", {
    capability = Capability.AddItem,
}, function(player, payload)
    Pallid.log("give item", payload.id, "to", player:getUsername())
end)
```

### Notes
- The value is passed unchanged to `Role.hasCapability(player, capability)`, which compares it against the role's set of `Capability` enum values.
- Obvious invalid values are rejected at registration: a `string`, `number`, `boolean` or `function` fails with `capability must be a Capability value`. A valid enum value (userdata) is accepted; a table is accepted for compatibility but fails closed at the role check.
- A `nil` player, or a player without a role, is denied.
- The check runs only when `isServer()` is true, so it is skipped for in-process singleplayer dispatch and the local player is never blocked there. A co-op host client is an ordinary multiplayer client, so its messages are still checked by the server process.
- Denial returns `false, "capability denied"` to the sender and logs `capability denied for action <action>` through `Pallid.warn`, at most once every 5 seconds.
- Rejected by [onClient](#pallidnetonclient) at registration.

## dedup

Optional replay protection for one server action.

**Side:** server

### Parameters
- dedup (boolean) - `true` enables the nonce ring for this action. Defaults to `false`.

### Example
```lua
Pallid.Net.onServer("Shop_buy", {
    dedup = true,
}, function(player, payload) end)
```

### Notes
- Every client-to-server envelope carries a random `n` nonce. When `dedup` is enabled the guard keeps the last 128 nonces per `(online id, action)` and rejects a nonce that is still in that window.
- A missing, non-numeric, non-finite or fractional nonce is rejected with `invalid dedup nonce`. A repeated nonce is rejected with `replayed nonce`.
- Rejections log `replayed action <action> for player <onlineID>` through `Pallid.warn`, at most once every 5 seconds.
- The ring is independent of packet ordering and survives reconnects because nonces are random, not sequential.
- Replay protection is opt-in. Idempotent actions such as the built-in moodle actions do not need it.
- Rejected by [onClient](#pallidnetonclient) at registration.

## Payload codec

Every outgoing and incoming payload is validated against the native transport rules before it is sent or dispatched.

**Side:** shared

| Rule | Limit | Reason |
| --- | --- | --- |
| Top-level value | `nil` rejected | The native envelope omits a `nil` payload key. |
| Value types | `string`, `number`, `boolean`, `table` | Other types are dropped by the native serializer. |
| Table keys | `string` or `number` only | Other keys are dropped by the native serializer. |
| String size | 32767 UTF-8 bytes | The native length prefix overflows and the string arrives empty. |
| Payload size | 262144 estimated bytes | The native packet buffer is 1000000 bytes. |
| Nesting depth | 8 tables | Bounds recursion in the native serializer. |
| Keys per table | 256 | Bounds traversal work. |
| Total nodes | 4096 | Bounds the whole payload. |
| Numbers | finite only | NaN and infinity have no stable wire form. |
| Cycles | rejected | The native serializer would recurse forever. |

### Notes
- The byte budget is an estimate, not an exact wire size: a string adds its byte length plus 3, a number 9, a boolean 2, and a table 5. Treat it as a safety margin, not as the exact packet size.
- String length is counted in UTF-8 bytes, not characters. A non-ASCII string such as Cyrillic text reaches the limit at half the character count.
- The depth limit counts tables. A scalar nested at depth 8 is accepted; a ninth nested table is rejected.
- Nested `nil` cannot be detected, because a Lua table never stores a `nil` value. Use a required schema field when absence must be rejected.
- Kahlua's table iterator copies the key set before the loop, so the 256-key limit is enforced after that copy. The native packet size and the per-action/global rate limits bound the worst case; a pure Lua codec cannot avoid the copy.
- Validation is read-only for the codec; only [schema](#schema) mutates the payload.
- A rejected send returns `false` with the reason and logs through `Pallid.warn`, throttled to one line every 5 seconds. A rejected incoming payload is dropped the same way.

## Singleplayer and multiplayer

The layer behaves differently depending on which process runs it.

**Side:** shared

### Notes
- Singleplayer: both `isServer()` and `isClient()` are false. `sendToServer` calls the server handler in-process, `send` and `broadcast` call the client handler in-process, and no native packet is used. The global per-player limit still applies to the local dispatch path.
- Multiplayer client: `isClient()` is true. Client-to-server messages go through `sendClientCommand` and server-to-client messages arrive through `Events.OnServerCommand`. Every client-to-server envelope carries the `n` nonce; server-to-client envelopes do not.
- Dedicated and co-op server process: `isServer()` is true. Server messages go through `sendServerCommand` and client messages arrive through `Events.OnClientCommand`.
- The server listener returns early when `isClient() and not isServer()`, and the client listener returns early when `isServer() and not isClient()`. This matters because the server Lua directory is also loaded on a multiplayer client for checksum parity.
- `onClient` handlers are looked up in the process that receives the message, so they must be registered from Lua that runs in the client process. Registering from shared Lua covers singleplayer and every multiplayer client.

## Action naming

Name every action `Owner_action`, for example `Shop_buy`, `Moodles_set` or `Faction_invite`.

**Side:** shared

### Notes
- The owner prefix keeps actions from different mods from colliding, because the handler tables are global to the process.
- The prefix is a convention, not enforced by the layer. An empty action name is rejected; any other string is accepted.
- The same action name can be registered once on the server side and once on the client side; those are separate tables.
