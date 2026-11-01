# Moodles

`Pallid.Moodles` registers custom moodles, keeps one numeric value per moodle on
each character and draws them in the native moodle column. Values are numbers
from 0 to 1; 0.5 is neutral and a neutral moodle is not displayed.

## Pallid.Moodles.add

Registers a moodle definition. Definitions are loaded on both sides, so the same
id must be registered on the client and on the server.

**Side:** shared

### Parameters
- spec (PallidMoodleSpec) - Moodle definition. See [Moodle spec](#moodle-spec-pallidmoodlespec).

### Returns
- PallidMoodle|nil - Registered definition, or nil when the spec is rejected.
- string|nil - Failure reason: `definition table expected`, `id required`, `invalid id`, `icon required`, `invalid clientWritable` or `duplicate id`.

### Example
```lua
local stress = Pallid.Moodles.add({
    id         = "mymod:stress",
    icon       = "media/ui/Moodles/stress.png",
    title      = { bad = { [1] = "Uneasy", [2] = "Stressed" } },
    thresholds = { bad4 = 0.05 },
    priority   = 10,
})

if stress ~= nil then
    stress:setValue(getPlayer(), 0.25)
end
```

### Notes
- The id must contain a namespace and a path (`^[^:]+:.+$`), for example `mymod:stress`.
- Ids are lower-cased, so `Mymod:Stress` and `mymod:stress` are the same moodle.
- `icon` is required even when `draw` is false; the built-in renderer never guesses a fallback texture.

## Moodle spec (PallidMoodleSpec)

Fields accepted by `Pallid.Moodles.add`.

**Side:** shared

### Parameters
- id (string) - Unique namespaced id, for example `"mymod:stress"`. Required.
- icon (string) - Texture path used when no per-level override applies. Required.
- title (string|table|nil) - Fixed title, or a table keyed by `"good"`/`"bad"` and then by level 1..4.
- description (string|table|nil) - Tooltip text with the same string-or-table rules as `title`.
- icons (table|nil) - Texture overrides keyed by `"good"`/`"bad"` and then by level 1..4.
- thresholds (table|nil) - Partial threshold overrides merged into the defaults. See [Thresholds and levels](#thresholds-and-levels).
- priority (number|nil) - Draw order; lower values are drawn first. Defaults to 0.
- draw (boolean|nil) - `false` keeps the moodle out of the built-in renderer. Defaults to true.
- clientWritable (boolean|nil) - `true` allows a multiplayer client to set this moodle through `Moodles_set`. Defaults to `false`, so gameplay-relevant moodles stay server-authoritative.

### Notes
- The spec table is kept as `definition.spec`, but the module copies the values it uses. Changing the spec table after registration does not change the definition.
- `title`, `description` and `icons` have no neutral group. A neutral moodle falls back to the id for the title, `""` for the description and `icon` for the texture.
- Text tables are looked up by level 1..4; a missing level falls back to the same defaults as a missing table.

## Thresholds and levels

Thresholds map a value to a level from 0 to 4. Level 0 means the moodle is not drawn.

**Side:** shared

### Notes
- Defaults: `bad4` 0.1, `bad3` 0.2, `bad2` 0.3, `bad1` 0.4, `good1` 0.6, `good2` 0.7, `good3` 0.8, `good4` 0.9.
- Level 4 when the value is `<= bad4` or `>= good4`; level 3 when `<= bad3` or `>= good3`; then 2, then 1; otherwise 0.
- With the defaults a value strictly between 0.4 and 0.6 is hidden even though its alignment is already good or bad.
- Exactly 0.5 always resolves to level 0 and alignment 0, whatever the thresholds are.
- Overrides are merged per key and converted with `tonumber`. Non-numeric values are ignored and unknown keys are stored but unused.
- A lower value always means "worse" and a higher value "better": the `bad*` keys bound values below 0.5 and the `good*` keys bound values above it.

## Pallid.Moodles.get

Returns the registered definition for an id.

**Side:** shared

### Parameters
- id (string) - Moodle id.

### Returns
- PallidMoodle|nil - Registered definition, or nil when the id is unknown or not a string.

### Example
```lua
local stress = Pallid.Moodles.get("mymod:stress")
```

## Pallid.Moodles.isRegistered

Returns whether a moodle id is registered.

**Side:** shared

### Parameters
- id (string) - Moodle id.

### Returns
- boolean - `true` when the id is registered.

### Example
```lua
if Pallid.Moodles.isRegistered("mymod:stress") then
    Pallid.Moodles.clear(getPlayer(), "mymod:stress")
end
```

## Pallid.Moodles.getValue

Returns the current value of a moodle for a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to read.
- id (string|PallidMoodle) - Moodle id or definition.

### Returns
- number - Value in 0..1; 0.5 when the moodle is unregistered, unset, or the character has no ModData.

### Example
```lua
local value = Pallid.Moodles.getValue(player, "mymod:stress")
```

### Notes
- Stored values are clamped on read, so an out-of-range ModData entry is reported inside 0..1.
- Reading does not create the ModData table; a character that never had a moodle written reports 0.5 for every id.

## Pallid.Moodles.setValue

Sets the value of a moodle for a character and replicates the change.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to modify.
- id (string|PallidMoodle) - Moodle id or definition.
- value (number) - New value. Values outside 0..1 are clamped; `nil` or NaN becomes 0.5.

### Returns
- boolean - `true` when a local write happened, `false` when nothing changed or the call was rejected.

### Example
```lua
local changed = Pallid.Moodles.setValue(player, "mymod:stress", 0.2)
```

### Notes
- The result means "changed", not "succeeded": writing the value the moodle already has returns `false`.
- An unregistered id or a missing player logs an error and returns `false`.
- On a multiplayer client, changing a remote player is rejected with a warning and returns `false`.
- On a multiplayer client, changing a moodle that was not registered with `clientWritable = true` is rejected with a warning and returns `false` before the optimistic write. Gameplay moodles are server-authoritative by default.
- On the server the value is written and pushed to the owning client. On a client the value is written optimistically and the server is asked to confirm it; the value that persists is the clamped one the server echoes back when it knows the moodle.

## Pallid.Moodles.getLevel

Returns the level derived from a moodle value.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to read.
- id (string|PallidMoodle) - Moodle id or definition.

### Returns
- number - Level 0..4; 0 for an unregistered moodle, a neutral value, or a value inside the dead zone.

### Example
```lua
local level = Pallid.Moodles.getLevel(player, "mymod:stress")
```

## Pallid.Moodles.getAlignment

Returns the alignment derived from a moodle value.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to read.
- id (string|PallidMoodle) - Moodle id or definition.

### Returns
- number - 0 neutral, 1 good (value above 0.5), 2 bad (value below 0.5); 0 for an unregistered moodle.

### Example
```lua
local alignment = Pallid.Moodles.getAlignment(player, "mymod:stress")
```

### Notes
- Alignment comes from the value alone, not from the level: a value of 0.45 is bad but has level 0 with the default thresholds.

## Pallid.Moodles.clear

Resets a moodle to the neutral value.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to modify.
- id (string|PallidMoodle) - Moodle id or definition.

### Returns
- boolean - `true` when the value changed, `false` when it was already neutral or the call was rejected.

### Example
```lua
Pallid.Moodles.clear(player, "mymod:stress")
```

### Notes
- This is `setValue` with 0.5, so it replicates exactly like a normal write.

## Pallid.Moodles.NEUTRAL_VALUE

The neutral value used by the module: `0.5`.

**Side:** shared

### Example
```lua
Pallid.Moodles.setValue(player, "mymod:stress", Pallid.Moodles.NEUTRAL_VALUE)
```

## PallidMoodle

Registered moodle definition returned by `Pallid.Moodles.add`.

**Side:** shared

### Notes
- Fields: `id` (normalized, lower-case), `spec`, `icon`, `icons`, `title`, `description`, `thresholds` (instance-owned copy of the merged thresholds), `priority`, `draw`, `clientWritable`.
- The registry owns the instance. Changing `thresholds` or `draw` afterwards changes behaviour. `priority` is only read during registration, so changing it later does not re-sort the draw order. `clientWritable` is read by the server handler and by the client-side `setValue` guard.

## PallidMoodle:getTitle

Returns the title for an alignment and level.

**Side:** shared

### Parameters
- alignment (number) - 0 neutral, 1 good, 2 bad.
- level (number) - Level 1..4.

### Returns
- string - Configured title, or the normalized id when nothing matches.

### Example
```lua
local title = stress:getTitle(2, 2)
```

## PallidMoodle:getDescription

Returns the description for an alignment and level.

**Side:** shared

### Parameters
- alignment (number) - 0 neutral, 1 good, 2 bad.
- level (number) - Level 1..4.

### Returns
- string - Configured description, or `""` when nothing matches.

### Example
```lua
local description = stress:getDescription(2, 2)
```

## PallidMoodle:getIconPath

Returns the texture path for an alignment and level.

**Side:** shared

### Parameters
- alignment (number) - 0 neutral, 1 good, 2 bad.
- level (number) - Level 1..4.

### Returns
- string - Matching `icons` override, or the base `icon`.

### Example
```lua
local path = stress:getIconPath(2, 3)
```

### Notes
- Only alignments 1 and 2 can resolve an override; neutral always returns the base `icon`.

## PallidMoodle:setValue

Sets this moodle's value for a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to modify.
- value (number) - New value in 0..1.

### Returns
- boolean - `true` when the value changed.

### Example
```lua
stress:setValue(player, 0.25)
```

## PallidMoodle:getValue

Returns this moodle's value for a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to read.

### Returns
- number - Value in 0..1; 0.5 when unset.

### Example
```lua
local value = stress:getValue(player)
```

## PallidMoodle:getLevel

Returns this moodle's level for a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to read.

### Returns
- number - Level 0..4.

### Example
```lua
local level = stress:getLevel(player)
```

## PallidMoodle:getAlignment

Returns this moodle's alignment for a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to read.

### Returns
- number - 0 neutral, 1 good, 2 bad.

### Example
```lua
local alignment = stress:getAlignment(player)
```

## PallidMoodle:clear

Resets this moodle to the neutral value.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to modify.

### Returns
- boolean - `true` when the value changed.

### Example
```lua
stress:clear(player)
```

## Pallid.Moodles.setRendererEnabled

Enables or disables the built-in renderer for custom moodles.

**Side:** client

### Parameters
- enabled (boolean|nil) - `false` disables drawing; any other value, including `nil`, enables it.

### Returns
- nil - No return value.

### Example
```lua
Pallid.Moodles.setRendererEnabled(false)
```

### Notes
- Disabling restores the Lua table that `MoodlesUI` had before the framework attached its callback.
- Values, synchronisation and `Pallid.Moodles.forEachVisible` keep working while drawing is disabled, so a mod can draw the moodles itself.
- Enabling again re-attaches to every active local player.

## Pallid.Moodles.isRendererEnabled

Returns whether the built-in renderer is enabled.

**Side:** client

### Returns
- boolean - `true` when the built-in renderer draws custom moodles.

### Example
```lua
if Pallid.Moodles.isRendererEnabled() then
    Pallid.Moodles.setRenderer(nil)
end
```

## Pallid.Moodles.setRenderer

Installs a custom renderer or restores the built-in one.

**Side:** client

### Parameters
- renderer (PallidMoodleRenderer|function|nil) - Table with a `render` method, a plain function, or `nil` for the built-in renderer.

### Returns
- boolean - `true` when the renderer was accepted, `false` for any other value.

### Example
```lua
Pallid.Moodles.setRenderer(function(element, player, entries, layout)
    for i = 1, #entries do
        local entry = entries[i]
        if entry.texture ~= nil and entry.definition.draw ~= false then
            local y = layout.firstY + (i - 1) * layout.spacing
            element:DrawTextureScaledColor(entry.texture, 0, y, layout.size, layout.size, 1, 1, 1, 1)
        end
    end
end)
```

### Notes
- The table form calls `renderer:render(element, player, entries, layout)`; the function form calls `renderer(element, player, entries, layout)`.
- The renderer runs only when at least one custom moodle is visible, and only while the built-in renderer is enabled.
- A renderer error is logged, the custom renderer is dropped and the built-in renderer draws that frame.
- The renderer receives no visible count. The entry array is reused and may still hold slots from earlier frames, so check each entry before drawing or use `forEachVisible` when an exact count matters.

## Pallid.Moodles.getLayout

Returns the cached layout of the custom moodle column for a player.

**Side:** client

### Parameters
- player (IsoPlayer) - Local player whose layout is requested.

### Returns
- number|nil - Absolute left coordinate of the native moodle column.
- number|nil - Absolute top coordinate of the first custom moodle slot.
- number|nil - Moodle size in pixels.
- number|nil - Vertical distance between moodle slots.
- number|nil - Number of visible native moodles above the custom list.

### Example
```lua
local x, y, size, spacing, nativeCount = Pallid.Moodles.getLayout(getPlayer())
```

### Notes
- Returns nothing (`nil`) when the player has no index or the native moodle element does not exist yet.
- The layout is recomputed at most every 250 ms unless the element changed, so a value read right after a UI change can be up to 250 ms old.

## Pallid.Moodles.forEachVisible

Calls a callback for every visible custom moodle of a player.

**Side:** client

### Parameters
- player (IsoPlayer) - Player whose moodles are iterated.
- callback (function) - Called with a reused entry table for each visible moodle.

### Returns
- number - Number of visible moodles.

### Example
```lua
local count = Pallid.Moodles.forEachVisible(player, function(entry)
    Pallid.log("moodle", entry.id, entry.level, entry.alignment)
end)
```

### Notes
- Only moodles with a level above 0 are visited; this includes moodles registered with `draw = false`.
- The entry passed to the callback is reused between calls and must not be stored or modified.
- Works while the built-in renderer is disabled, so it is the supported way to draw moodles with a custom widget.
- A missing player or a non-function callback returns 0 without an error.

## PallidMoodleEntry

Entry table passed to `Pallid.Moodles.forEachVisible` callbacks and to custom renderers.

**Side:** client

### Notes
- Fields: `id` (string), `definition` (PallidMoodle), `value` (number 0..1), `level` (number 0..4), `alignment` (number 0/1/2), `texture` (`Texture` or nil when the icon cannot be loaded), `title` (string), `description` (string).
- The table is reused. Read the fields inside the callback and copy anything you need to keep.
- `texture` is only refreshed when the definition, level or alignment changes.

## Multiplayer behaviour

Moodle values are stored per character and synchronised through [Pallid.Net](net.md).

**Side:** shared

### Notes
- The server is authoritative. A client write is optimistic and is corrected by the value the server sends back.
- Only moodles registered with `clientWritable = true` accept client writes. For every other moodle the server rejects `Moodles_set` with a throttled warning and the client-side `setValue` returns `false` before writing. This keeps gameplay-relevant moodles server-authoritative by default.
- A client asks for its full state when a local player is created and again when the world finishes loading.
- Server handlers for moodle requests and updates are rate limited to 20 messages per 10 seconds per player; messages over the limit are dropped. The global `Pallid.Net` per-player limit also applies.
- The `Moodles_set` schema limits `id` to 256 UTF-16 units and requires `value` to be a number. The `Moodles_state` client schema requires `onlineID` to be a number and `values` to be a number map; non-numeric values are rejected.
- The server ignores ids it has not registered, so an update for a client-only moodle is dropped and never confirmed. Unknown-id and server-owned warnings are sanitized, truncated and throttled.
- The server echoes a `Moodles_set` value only after the value was applied successfully.
- A client cannot change the moodles of another player; such a call is rejected with a warning.

## ModData persistence

Moodle values live in the character's ModData.

**Side:** shared

### Notes
- All values are stored in one table under the ModData key `Pallid_Moodles`, keyed by normalized moodle id.
- The table is saved with the character, so values survive save and load without extra code.
- Only registered ids are read back and sent to clients; stale entries for removed moodles stay in the table and are ignored.
