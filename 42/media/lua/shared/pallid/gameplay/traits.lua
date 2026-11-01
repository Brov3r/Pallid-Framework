require "utils/logger"

Pallid = Pallid or {}
Pallid.Traits = Pallid.Traits or {}

local Traits = Pallid.Traits
local logger = Pallid.getLogger("Traits")

--- Flag passed to sendSyncPlayerFields to replicate the player's trait list.
--- Verified against zombie.network.packets.SyncPlayerFieldsPacket.PF_Traits.
local SYNC_PARAM_TRAITS = 2

--- Definition accepted by Pallid.Traits.add.
---@class PallidTraitSpec
---@field id string Registry id with a namespace, e.g. "mymod:brave2".
---@field name string Translation key or literal display name.
---@field description string|nil Translation key or literal description.
---@field cost integer|nil Trait cost; negative values mark a bad trait.
---@field hidden boolean|nil Hides the trait from character creation by marking it as a profession trait.
---@field professionTrait boolean|nil Explicit low-level flag equivalent to CharacterTraitDefinition.isProfessionTrait.
---@field disabledInMultiplayer boolean|nil Whether the trait is disabled in multiplayer.
---@field icon string|nil Texture path used for the trait icon.
---@field xpBoosts table|nil Map of PerkFactory.Perk to an integer boost amount.
---@field grantedTraits table|nil Array of trait ids or PallidTrait objects granted by this trait.
---@field grantedRecipes table|nil Array of recipe names granted by this trait.
---@field mutuallyExclusive table|nil Array of trait ids or PallidTrait objects that cannot be selected together.

--- Registered trait wrapper returned by Pallid.Traits.add.
---@class PallidTrait
---@field id string Normalized registry id.
---@field type CharacterTrait Native trait registry object.
---@field definition CharacterTraitDefinition Native trait definition.
---@field spec PallidTraitSpec The spec used to register the trait.
local PallidTrait = {}
PallidTrait.__index = PallidTrait

--- Registered traits keyed by normalized registry id.
---@type table<string, PallidTrait>
local registry = {}

--- Registered traits in registration order.
---@type PallidTrait[]
local registrationOrder = {}

--- Returns the lower-case registry id used by ResourceLocation.
---@param id string Registry id or plain trait name.
---@return string normalized Normalized id.
local function normalizeId(id)
    return string.lower(tostring(id))
end

--- Resolves a string or wrapped trait to a native CharacterTrait.
---@param value string|PallidTrait|CharacterTrait Trait id, wrapper or native trait.
---@return CharacterTrait|nil trait Native trait when it can be resolved.
local function resolveTrait(value)
    if type(value) == "string" then
        local entry = registry[normalizeId(value)]
        if entry ~= nil then
            return entry.type
        end

        local okLocation, location = pcall(ResourceLocation.of, value)
        if not okLocation then
            return nil
        end

        local okTrait, trait = pcall(CharacterTrait.get, location)
        if not okTrait then
            return nil
        end
        return trait
    end

    if type(value) == "table" then
        return value.type
    end

    return value
end

--- Resolves a native trait to its definition.
---@param trait CharacterTrait Native trait.
---@return CharacterTraitDefinition|nil definition Native definition when registered.
local function getDefinition(trait)
    if trait == nil then
        return nil
    end

    local ok, definition = pcall(CharacterTraitDefinition.getCharacterTraitDefinition, trait)
    if not ok then
        return nil
    end
    return definition
end

--- Returns the native trait map of a character or nil when the object is invalid.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return CharacterTraits|nil characterTraits Native trait collection.
local function getCharacterTraits(player)
    if player == nil or player.getCharacterTraits == nil then
        return nil
    end

    local ok, traits = pcall(player.getCharacterTraits, player)
    if not ok then
        return nil
    end
    return traits
end

--- Replicates the trait list of a player to clients when running on a server.
---@param player IsoPlayer Player whose traits changed.
local function syncPlayerTraits(player)
    if not isServer() or player == nil or not instanceof(player, "IsoPlayer") then
        return
    end

    local ok, err = pcall(sendSyncPlayerFields, player, SYNC_PARAM_TRAITS)
    if not ok then
        logger:error("failed to sync traits for", tostring(player), ":", tostring(err))
    end
end

--- Adds a mutually exclusive link in one direction when both definitions exist.
---@param definition CharacterTraitDefinition Definition receiving the exclusion.
---@param other CharacterTrait Trait that cannot be selected together.
local function addExclusion(definition, other)
    if definition == nil or other == nil then
        return
    end

    local exclusions = definition:getMutuallyExclusiveTraits()
    if not exclusions:contains(other) then
        definition:addMutuallyExclusive(other)
    end
end

--- Re-resolves all declared mutual exclusions for registered traits.
--- Runs after each registration so forward references are resolved once the
--- referenced trait becomes available.
local function resolveMutualExclusions()
    for i = 1, #registrationOrder do
        local entry = registrationOrder[i]
        local definition = entry.definition
        local declared = entry.spec.mutuallyExclusive

        if definition ~= nil and type(declared) == "table" then
            for j = 1, #declared do
                local other = resolveTrait(declared[j])
                local otherDefinition = getDefinition(other)
                if otherDefinition ~= nil and other ~= entry.type then
                    addExclusion(definition, other)
                    addExclusion(otherDefinition, entry.type)
                end
            end
        end
    end
end

--- Applies a single XP boost described by the spec.
---@param definition CharacterTraitDefinition Definition receiving the boost.
---@param perk PerkFactory.Perk Perk to boost.
---@param level any Boost amount converted to an integer.
local function applyXpBoost(definition, perk, level)
    local amount = math.floor(tonumber(level) or 0)
    if perk ~= nil and amount ~= 0 then
        definition:addXPBoost(perk, amount)
    end
end

--- Applies granted traits, recipes and XP boosts to a fresh definition.
---@param entry PallidTrait Wrapper being registered.
local function applySpec(entry)
    local definition = entry.definition
    local spec = entry.spec

    if spec.icon ~= nil then
        if type(spec.icon) == "string" then
            -- Dedicated servers do not load client textures. A listen server
            -- also runs client UI, so it still applies the icon.
            if not (isServer() and not isClient()) then
                local texture = getTexture(spec.icon)
                if texture ~= nil then
                    definition:setTexture(texture)
                else
                    logger:warn("trait icon not found:", spec.icon)
                end
            end
        else
            logger:warn("ignoring invalid trait icon for", entry.id)
        end
    end

    if type(spec.xpBoosts) == "table" then
        for perk, level in pairs(spec.xpBoosts) do
            applyXpBoost(definition, perk, level)
        end
    end

    if type(spec.grantedRecipes) == "table" then
        for i = 1, #spec.grantedRecipes do
            local recipe = spec.grantedRecipes[i]
            if type(recipe) == "string" and recipe ~= "" then
                definition:addGrantedRecipe(recipe)
            else
                logger:warn("ignoring invalid granted recipe for", entry.id)
            end
        end
    end
end

--- Re-resolves declared granted traits for registered definitions.
--- Runs after each registration so a trait may reference a trait defined later
--- in the same load pass.
local function resolveGrantedTraits()
    for i = 1, #registrationOrder do
        local entry = registrationOrder[i]
        if entry._createdDefinition and type(entry.spec.grantedTraits) == "table" then
            local grantedTraits = entry.definition:getGrantedTraits()

            for j = 1, #entry.spec.grantedTraits do
                local granted = resolveTrait(entry.spec.grantedTraits[j])
                if granted ~= nil and granted ~= entry.type
                    and getDefinition(granted) ~= nil and not grantedTraits:contains(granted) then
                    entry.definition:addGrantedTrait(granted)
                    grantedTraits = entry.definition:getGrantedTraits()
                end
            end
        end
    end
end

--- Registers a trait definition.
---
--- Must be called while shared Lua loads, before character creation. If a script
--- file refers to the same trait before Lua loads, register the id in the mod's
--- media/registries.lua and this function will reuse that registry entry.
---
--- @param spec PallidTraitSpec Trait definition.
--- @return PallidTrait|nil trait Registered wrapper, or nil when the spec is invalid.
--- @return string|nil error Description of the validation failure.
function Traits.add(spec)
    if type(spec) ~= "table" then
        logger:error("Pallid.Traits.add expects a definition table")
        return nil, "definition table expected"
    end

    if type(spec.id) ~= "string" or spec.id == "" then
        logger:error("Pallid.Traits.add requires a non-empty id")
        return nil, "id required"
    end

    if string.match(spec.id, "^[^:]+:.+$") == nil then
        logger:error("trait id must include a namespace and a path:", tostring(spec.id))
        return nil, "invalid id"
    end

    if type(spec.name) ~= "string" or spec.name == "" then
        logger:error("Pallid.Traits.add requires a non-empty name for", spec.id)
        return nil, "name required"
    end

    local id = normalizeId(spec.id)
    local existing = registry[id]
    if existing ~= nil then
        logger:warn("trait already registered through Pallid, reusing:", id)
        return existing
    end

    local trait = resolveTrait(id)
    if trait == nil then
        local ok, result = pcall(CharacterTrait.register, id)
        if not ok then
            logger:error("failed to register trait", id, ":", tostring(result))
            return nil, "character trait registration failed"
        end
        trait = result
    end

    local createdDefinition = false
    local definition = getDefinition(trait)
    if definition ~= nil then
        logger:warn("trait definition already exists, reusing without changes:", id)
    else
        local hidden = spec.hidden == true or spec.professionTrait == true
        local description = ""
        if spec.description ~= nil then
            description = tostring(spec.description)
        end
        local ok, result = pcall(
            CharacterTraitDefinition.addCharacterTraitDefinition,
            trait,
            spec.name,
            math.floor(tonumber(spec.cost) or 0),
            description,
            hidden,
            spec.disabledInMultiplayer == true
        )
        if not ok then
            logger:error("failed to create trait definition", id, ":", tostring(result))
            return nil, "character trait definition failed"
        end
        definition = result
        createdDefinition = true
    end

    local entry = setmetatable({
        id                 = id,
        type               = trait,
        definition         = definition,
        spec               = spec,
        _createdDefinition = createdDefinition,
    }, PallidTrait)

    registry[id] = entry
    registrationOrder[#registrationOrder + 1] = entry

    if createdDefinition then
        -- A pre-existing script definition is intentionally left untouched.
        applySpec(entry)
    end

    resolveMutualExclusions()
    resolveGrantedTraits()
    logger:info("registered trait", id)
    return entry
end

--- Returns a trait registered through Pallid.Traits.
---@param id string Registry id.
---@return PallidTrait|nil trait Registered wrapper or nil.
function Traits.get(id)
    if type(id) ~= "string" then
        return nil
    end
    return registry[normalizeId(id)]
end

--- Returns whether a trait was registered through Pallid.Traits.
---@param id string Registry id.
---@return boolean registered True when the trait is known to this module.
function Traits.isRegistered(id)
    return type(id) == "string" and registry[normalizeId(id)] ~= nil
end

--- Grants a trait to a character.
---
--- In multiplayer call this on the server. The native PF_Traits packet is sent
--- to clients after a successful change.
---
--- @param player IsoGameCharacter|IsoPlayer Character receiving the trait.
--- @param value string|PallidTrait|CharacterTrait Trait id or wrapper.
--- @return boolean changed True when the trait was added by this call.
function Traits.grant(player, value)
    local trait = resolveTrait(value)
    local characterTraits = getCharacterTraits(player)

    if trait == nil or characterTraits == nil then
        logger:error("cannot grant trait:", tostring(value))
        return false
    end

    if not isServer() and isClient() and instanceof(player, "IsoPlayer")
        and not player:isLocalPlayer() then
        logger:warn("ignored trait change for a remote player on a client:", tostring(trait))
        return false
    end

    local nativeTraits = characterTraits:getTraits()
    if nativeTraits == nil or not nativeTraits:containsKey(trait) then
        logger:error("trait was registered after the character was created:", tostring(trait))
        return false
    end

    if player:hasTrait(trait) then
        return false
    end

    characterTraits:add(trait)
    syncPlayerTraits(player)
    return true
end

--- Removes a trait from a character.
---
--- In multiplayer call this on the server. The native PF_Traits packet is sent
--- to clients after a successful change.
---
--- @param player IsoGameCharacter|IsoPlayer Character losing the trait.
--- @param value string|PallidTrait|CharacterTrait Trait id or wrapper.
--- @return boolean changed True when the trait was removed by this call.
function Traits.revoke(player, value)
    local trait = resolveTrait(value)
    local characterTraits = getCharacterTraits(player)

    if trait == nil or characterTraits == nil then
        logger:error("cannot revoke trait:", tostring(value))
        return false
    end

    if not isServer() and isClient() and instanceof(player, "IsoPlayer")
        and not player:isLocalPlayer() then
        logger:warn("ignored trait change for a remote player on a client:", tostring(trait))
        return false
    end

    local nativeTraits = characterTraits:getTraits()
    if nativeTraits == nil or not nativeTraits:containsKey(trait) then
        logger:error("trait was registered after the character was created:", tostring(trait))
        return false
    end

    if not player:hasTrait(trait) then
        return false
    end

    characterTraits:remove(trait)
    syncPlayerTraits(player)
    return true
end

--- Returns whether a character has a trait.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@param value string|PallidTrait|CharacterTrait Trait id or wrapper.
---@return boolean hasTrait True when the character has the trait.
function Traits.has(player, value)
    local trait = resolveTrait(value)
    local characterTraits = getCharacterTraits(player)

    if trait == nil or characterTraits == nil then
        return false
    end

    local nativeTraits = characterTraits:getTraits()
    if nativeTraits == nil or not nativeTraits:containsKey(trait) then
        return false
    end

    return player:hasTrait(trait)
end

--- Adds this trait to a character.
---@param player IsoGameCharacter|IsoPlayer Character receiving the trait.
---@return boolean changed True when the trait was added.
function PallidTrait:grant(player)
    return Traits.grant(player, self)
end

--- Removes this trait from a character.
---@param player IsoGameCharacter|IsoPlayer Character losing the trait.
---@return boolean changed True when the trait was removed.
function PallidTrait:revoke(player)
    return Traits.revoke(player, self)
end

--- Returns whether a character has this trait.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return boolean hasTrait True when the character has the trait.
function PallidTrait:has(player)
    return Traits.has(player, self)
end

--- Returns the native CharacterTrait object.
---@return CharacterTrait trait Native trait registry object.
function PallidTrait:getType()
    return self.type
end

--- Returns the native CharacterTraitDefinition object.
---@return CharacterTraitDefinition definition Native trait definition.
function PallidTrait:getDefinition()
    return self.definition
end

Traits.PallidTrait = PallidTrait

return Pallid
