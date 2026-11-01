# Professions

`Pallid.Professions` registers character professions that appear on the
character-creation screen. A profession is chosen once at creation; the module
has no runtime grant or revoke.

## Pallid.Professions.add

Registers a profession definition. Must run while shared Lua loads, before the
character-creation screen is built.

**Side:** shared

### Parameters
- spec (PallidProfessionSpec) - Profession definition. See [Profession spec](#profession-spec-pallidprofessionspec).

### Returns
- PallidProfession|nil - Registered wrapper, or nil when the spec is rejected.
- string|nil - Failure reason: `definition table expected`, `id required`, `invalid id`, `name required`, `character profession registration failed` or `character profession definition failed`.

### Example
```lua
local mechanic2 = Pallid.Professions.add({
    id            = "mymod:mechanic2",
    name          = "UI_prof_mechanic2",
    description   = "UI_prof_mechanic2_desc",
    cost          = 2,
    icon          = "media/ui/Professions/mechanic2.png",
    xpBoosts      = { [PerkFactory.Perks.Mechanics] = 2 },
    grantedTraits = { "mymod:greaseMonkey" },
})
```

### Notes
- Registering the same Pallid id twice returns the existing wrapper with a warning and no error string.
- If a definition already exists for the id, it is reused unchanged: `name`, `cost`, `description`, `icon`, `xpBoosts`, `grantedRecipes` and `grantedTraits` are not applied. `name` is still validated.
- The native profession list and its descriptions are generated during `OnGameBoot`, so a profession registered after that point is not shown in character creation.

## Profession spec (PallidProfessionSpec)

Fields accepted by `Pallid.Professions.add`.

**Side:** shared

### Parameters
- id (string) - Unique namespaced id, for example `"mymod:mechanic2"`. Required and lower-cased.
- name (string) - Translation key or literal display name. Required.
- description (string|nil) - Translation key or literal description; defaults to `""`.
- cost (integer|nil) - Profession cost, floored; defaults to 0. Negative values are passed to the native definition unchanged.
- icon (string|nil) - Texture path stored on the native profession definition.
- xpBoosts (table|nil) - Map of `PerkFactory.Perk` to an integer boost, for example `{ [PerkFactory.Perks.Mechanics] = 2 }`. Zero amounts are skipped.
- grantedTraits (table|nil) - Array of trait ids or `PallidTrait` objects granted when the profession is chosen.
- grantedRecipes (table|nil) - Array of recipe names granted by the profession. Empty or non-string entries are skipped with a warning.

### Notes
- The icon is a path string handed to the native definition; unlike traits, the framework does not load it as a `Texture`.
- There is no `hidden`, `disabledInMultiplayer` or mutual-exclusion field for professions.
- `grantedTraits` entries are resolved as native traits. They are resolved again on `OnGameBoot`, so a profession may reference a trait registered later in the same load pass.
- Vanilla registers its own `OnGameBoot` handler first, so the profession description may be generated before that second pass; the granted trait is still applied when the profession is selected.
- Perk constants live on `PerkFactory.Perks` (for example `PerkFactory.Perks.Mechanics`); `PerkFactory.Perk` is the value type.

## Pallid.Professions.get

Returns a profession registered through this module.

**Side:** shared

### Parameters
- id (string) - Registry id.

### Returns
- PallidProfession|nil - Registered wrapper, or nil when the id is unknown or not a string.

### Example
```lua
local mechanic2 = Pallid.Professions.get("mymod:mechanic2")
```

### Notes
- Only professions registered through `Pallid.Professions.add` are returned.

## Pallid.Professions.isRegistered

Returns whether a profession was registered through this module.

**Side:** shared

### Parameters
- id (string) - Registry id.

### Returns
- boolean - `true` when the profession is known to this module.

### Example
```lua
if Pallid.Professions.isRegistered("mymod:mechanic2") then
    Pallid.log("profession available")
end
```

## PallidProfession

Registered profession wrapper returned by `Pallid.Professions.add`.

**Side:** shared

### Notes
- Fields: `id` (normalized, lower-case), `type` (native `CharacterProfession`), `definition` (native `CharacterProfessionDefinition`), `spec`.
- The wrapper exposes no runtime API beyond the two getters below; profession effects are applied by the game when the profession is selected.

## PallidProfession:getType

Returns the native profession object.

**Side:** shared

### Returns
- CharacterProfession - Native profession registry object.

### Example
```lua
local profession = mechanic2:getType()
```

## PallidProfession:getDefinition

Returns the native profession definition.

**Side:** shared

### Returns
- CharacterProfessionDefinition - Native definition created or reused by `Pallid.Professions.add`.

### Example
```lua
local definition = mechanic2:getDefinition()
Pallid.log(definition:getCost())
```

## Character creation only

Professions are a character-creation feature, not a runtime state change.

**Side:** shared

### Notes
- Register professions during shared Lua load; client and server then build the same definition list for character creation.
- XP boosts, granted traits and granted recipes are applied by the game when the player confirms the profession, so there is no `grant` equivalent to call later.
