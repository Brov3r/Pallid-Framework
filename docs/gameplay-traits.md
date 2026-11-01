# Traits

`Pallid.Traits` registers character traits, grants and revokes them at runtime,
and replicates changes from the server. Traits are stored natively on the
character; this module does not use ModData.

## Pallid.Traits.add

Registers a trait definition. Must run while shared Lua loads, before any
character is created.

**Side:** shared

### Parameters
- spec (PallidTraitSpec) - Trait definition. See [Trait spec](#trait-spec-pallidtraitspec).

### Returns
- PallidTrait|nil - Registered wrapper, or nil when the spec is rejected.
- string|nil - Failure reason: `definition table expected`, `id required`, `invalid id`, `name required`, `character trait registration failed` or `character trait definition failed`.

### Example
```lua
local brave2 = Pallid.Traits.add({
    id       = "mymod:brave2",
    name     = "UI_trait_brave2",
    cost     = 4,
    icon     = "media/ui/Traits/trait_brave2.png",
    xpBoosts = { [PerkFactory.Perks.Axe] = 1 },
})

if brave2 ~= nil then
    brave2:grant(getPlayer())
end
```

### Notes
- Registering the same Pallid id twice returns the existing wrapper with a warning and no error string.
- If the native trait exists but has no definition, a definition is created from the spec.
- If a definition already exists (for example a trait defined by a script), it is reused unchanged: `icon`, `name`, `cost`, `description`, `hidden`, `professionTrait`, `disabledInMultiplayer`, `xpBoosts` and `grantedRecipes` are not applied. `name` is still validated.
- If a script refers to the trait id before Lua loads, list the id in the mod's `media/registries.lua`; the existing native trait object is reused and a missing definition is still created from the spec.
- `mutuallyExclusive` is still resolved for a reused definition, because it only adds native exclusion links.
- Call this before characters are created. A trait registered later cannot be granted to a character that already exists.

## Trait spec (PallidTraitSpec)

Fields accepted by `Pallid.Traits.add`.

**Side:** shared

### Parameters
- id (string) - Unique namespaced id, for example `"mymod:brave2"`. Required and lower-cased.
- name (string) - Translation key or literal display name. Required.
- description (string|nil) - Translation key or literal description; defaults to `""`.
- cost (integer|nil) - Trait cost, floored; defaults to 0. Negative values are passed to the native definition unchanged.
- hidden (boolean|nil) - Marks the trait as a profession trait so it is not offered in character creation.
- professionTrait (boolean|nil) - Same effect as `hidden`; the low-level native flag.
- disabledInMultiplayer (boolean|nil) - Passes the native disabled-in-multiplayer flag.
- icon (string|nil) - Texture path loaded with `getTexture` and applied to the definition.
- xpBoosts (table|nil) - Map of `PerkFactory.Perk` to an integer boost, for example `{ [PerkFactory.Perks.Axe] = 1 }`. Zero amounts are skipped.
- grantedTraits (table|nil) - Array of trait ids or `PallidTrait` objects granted together with this trait.
- grantedRecipes (table|nil) - Array of recipe names granted by the trait. Empty or non-string entries are skipped with a warning.
- mutuallyExclusive (table|nil) - Array of trait ids or `PallidTrait` objects that cannot be selected together with this trait.

### Notes
- `hidden` and `professionTrait` are equivalent; either one sets the native profession flag.
- `grantedTraits` and `mutuallyExclusive` accept forward references: both are re-resolved after every registration, so a trait may point at a trait registered later in the same load pass.
- Mutual exclusions are added in both directions and a self reference is ignored.
- Perk constants live on `PerkFactory.Perks` (for example `PerkFactory.Perks.Axe`); `PerkFactory.Perk` is the value type.
- On a dedicated server the icon is skipped, because client textures are not loaded there. A listen server still applies it.

## Pallid.Traits.get

Returns a trait registered through this module.

**Side:** shared

### Parameters
- id (string) - Registry id.

### Returns
- PallidTrait|nil - Registered wrapper, or nil when the id is unknown or not a string.

### Example
```lua
local brave2 = Pallid.Traits.get("mymod:brave2")
```

### Notes
- Only traits registered through `Pallid.Traits.add` are returned. A vanilla or script-defined trait is not in this registry.

## Pallid.Traits.isRegistered

Returns whether a trait was registered through this module.

**Side:** shared

### Parameters
- id (string) - Registry id.

### Returns
- boolean - `true` when the trait is known to this module.

### Example
```lua
if Pallid.Traits.isRegistered("mymod:brave2") then
    Pallid.Traits.grant(player, "mymod:brave2")
end
```

## Pallid.Traits.grant

Adds a trait to a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character receiving the trait.
- value (string|PallidTrait|CharacterTrait) - Trait id, wrapper or native trait.

### Returns
- boolean - `true` when this call added the trait.

### Example
```lua
local granted = Pallid.Traits.grant(player, "mymod:brave2")
```

### Notes
- Returns `false` when the character already has the trait, when the trait cannot be resolved, or when the character is invalid.
- Returns `false` with an error when the trait is missing from the character's native trait list; that means the trait was registered after the character was created.
- On the server the change is replicated to clients through the native trait field sync.
- On a multiplayer client, changing a remote player is rejected. Changing the local player succeeds locally but is not sent to the server, so the next server sync can overwrite it.

## Pallid.Traits.revoke

Removes a trait from a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character losing the trait.
- value (string|PallidTrait|CharacterTrait) - Trait id, wrapper or native trait.

### Returns
- boolean - `true` when this call removed the trait.

### Example
```lua
local removed = Pallid.Traits.revoke(player, "mymod:brave2")
```

### Notes
- Returns `false` when the character does not have the trait, when the trait cannot be resolved, or when the character is invalid.
- The same registration-order and multiplayer rules as `Pallid.Traits.grant` apply.

## Pallid.Traits.has

Returns whether a character has a trait.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to inspect.
- value (string|PallidTrait|CharacterTrait) - Trait id, wrapper or native trait.

### Returns
- boolean - `true` when the character has the trait.

### Example
```lua
if Pallid.Traits.has(player, "mymod:brave2") then
    Pallid.log("already brave")
end
```

### Notes
- Read-only and safe on both sides.
- Returns `false` for an unknown trait and for a trait that is not part of the character's native trait list.

## PallidTrait

Registered trait wrapper returned by `Pallid.Traits.add`.

**Side:** shared

### Notes
- Fields: `id` (normalized, lower-case), `type` (native `CharacterTrait`), `definition` (native `CharacterTraitDefinition`), `spec`.
- Use the methods below instead of mutating the native objects directly, so multiplayer replication is not skipped.

## PallidTrait:grant

Adds this trait to a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character receiving the trait.

### Returns
- boolean - `true` when the trait was added.

### Example
```lua
brave2:grant(player)
```

## PallidTrait:revoke

Removes this trait from a character.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character losing the trait.

### Returns
- boolean - `true` when the trait was removed.

### Example
```lua
brave2:revoke(player)
```

## PallidTrait:has

Returns whether a character has this trait.

**Side:** shared

### Parameters
- player (IsoGameCharacter|IsoPlayer) - Character to inspect.

### Returns
- boolean - `true` when the character has the trait.

### Example
```lua
if brave2:has(player) then
    Pallid.log("brave")
end
```

## PallidTrait:getType

Returns the native trait object.

**Side:** shared

### Returns
- CharacterTrait - Native trait registry object.

### Example
```lua
local trait = brave2:getType()
```

## PallidTrait:getDefinition

Returns the native trait definition.

**Side:** shared

### Returns
- CharacterTraitDefinition - Native definition created or reused by `Pallid.Traits.add`.

### Example
```lua
local definition = brave2:getDefinition()
Pallid.log(definition:getCost())
```

## Multiplayer behaviour

Trait changes are replicated with the native trait sync.

**Side:** shared

### Notes
- Register the same traits on both sides before characters exist. A client cannot resolve a trait id that only the server registered.
- Call `grant` and `revoke` on the server; the framework sends the native `PF_Traits` field sync to clients after a successful change.
- Calling them on a multiplayer client only changes local state, because only the server sends the sync packet.
- `Pallid.Traits.has` and `PallidTrait:has` are safe to call anywhere and never replicate.
