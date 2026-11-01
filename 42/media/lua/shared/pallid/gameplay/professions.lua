require "utils/logger"

Pallid = Pallid or {}
Pallid.Professions = Pallid.Professions or {}

local Professions = Pallid.Professions
local logger = Pallid.getLogger("Professions")

--- Definition accepted by Pallid.Professions.add.
---@class PallidProfessionSpec
---@field id string Registry id with a namespace, e.g. "mymod:mechanic2".
---@field name string Translation key or literal display name.
---@field description string|nil Translation key or literal description.
---@field cost integer|nil Profession cost; negative values are allowed by the native definition.
---@field icon string|nil Texture path used for the profession icon.
---@field xpBoosts table|nil Map of PerkFactory.Perk to an integer boost amount.
---@field grantedTraits table|nil Array of trait ids or PallidTrait objects granted by the profession.
---@field grantedRecipes table|nil Array of recipe names granted by the profession.

--- Registered profession wrapper returned by Pallid.Professions.add.
---@class PallidProfession
---@field id string Normalized registry id.
---@field type CharacterProfession Native profession registry object.
---@field definition CharacterProfessionDefinition Native profession definition.
---@field spec PallidProfessionSpec The spec used to register the profession.
local PallidProfession = {}
PallidProfession.__index = PallidProfession

--- Registered professions keyed by normalized registry id.
---@type table<string, PallidProfession>
local registry = {}

--- Registered professions in registration order.
---@type PallidProfession[]
local registrationOrder = {}

--- Returns the lower-case registry id used by ResourceLocation.
---@param id string Registry id or plain profession name.
---@return string normalized Normalized id.
local function normalizeId(id)
    return string.lower(tostring(id))
end

--- Resolves a string or wrapped trait to a native CharacterTrait.
---@param value string|PallidTrait|CharacterTrait Trait id, wrapper or native trait.
---@return CharacterTrait|nil trait Native trait when it can be resolved.
local function resolveTrait(value)
    if type(value) == "string" then
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

--- Resolves a native profession to its definition.
---@param profession CharacterProfession Native profession.
---@return CharacterProfessionDefinition|nil definition Native definition when registered.
local function getDefinition(profession)
    if profession == nil then
        return nil
    end

    local ok, definition = pcall(CharacterProfessionDefinition.getCharacterProfessionDefinition, profession)
    if not ok then
        return nil
    end
    return definition
end

--- Applies granted traits, recipes and XP boosts to a fresh definition.
---@param entry PallidProfession Wrapper being registered.
local function applySpec(entry)
    local definition = entry.definition
    local spec = entry.spec

    if type(spec.xpBoosts) == "table" then
        for perk, level in pairs(spec.xpBoosts) do
            local amount = math.floor(tonumber(level) or 0)
            if perk ~= nil and amount ~= 0 then
                definition:addXPBoost(perk, amount)
            end
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

--- Re-resolves granted traits for registered professions.
--- Runs after each registration and once during OnGameBoot so a profession may
--- reference a trait that is registered later in the load pass.
local function resolveGrantedTraits()
    for i = 1, #registrationOrder do
        local entry = registrationOrder[i]
        if entry._createdDefinition and type(entry.spec.grantedTraits) == "table" then
            local grantedTraits = entry.definition:getGrantedTraits()

            for j = 1, #entry.spec.grantedTraits do
                local trait = resolveTrait(entry.spec.grantedTraits[j])
                if trait ~= nil and not grantedTraits:contains(trait) then
                    local ok, err = pcall(entry.definition.addGrantedTrait, entry.definition, trait)
                    if ok then
                        grantedTraits = entry.definition:getGrantedTraits()
                    else
                        logger:warn("failed to grant trait for", entry.id, ":", tostring(err))
                    end
                end
            end
        end
    end
end

--- Registers a profession definition.
---
--- Must be called while shared Lua loads, before character creation. The native
--- profession list and its descriptions are built during OnGameBoot.
---
--- @param spec PallidProfessionSpec Profession definition.
--- @return PallidProfession|nil profession Registered wrapper, or nil when the spec is invalid.
--- @return string|nil error Description of the validation failure.
function Professions.add(spec)
    if type(spec) ~= "table" then
        logger:error("Pallid.Professions.add expects a definition table")
        return nil, "definition table expected"
    end

    if type(spec.id) ~= "string" or spec.id == "" then
        logger:error("Pallid.Professions.add requires a non-empty id")
        return nil, "id required"
    end

    if string.match(spec.id, "^[^:]+:.+$") == nil then
        logger:error("profession id must include a namespace and a path:", tostring(spec.id))
        return nil, "invalid id"
    end

    if type(spec.name) ~= "string" or spec.name == "" then
        logger:error("Pallid.Professions.add requires a non-empty name for", spec.id)
        return nil, "name required"
    end

    local id = normalizeId(spec.id)
    local existing = registry[id]
    if existing ~= nil then
        logger:warn("profession already registered through Pallid, reusing:", id)
        return existing
    end

    local profession = nil
    local okGet, found = pcall(CharacterProfession.get, ResourceLocation.of(id))
    if okGet then
        profession = found
    end

    if profession == nil then
        local ok, result = pcall(CharacterProfession.register, id)
        if not ok then
            logger:error("failed to register profession", id, ":", tostring(result))
            return nil, "character profession registration failed"
        end
        profession = result
    end

    local createdDefinition = false
    local definition = getDefinition(profession)
    if definition ~= nil then
        logger:warn("profession definition already exists, reusing without changes:", id)
    else
        local description = ""
        if spec.description ~= nil then
            description = tostring(spec.description)
        end

        local iconPath = nil
        if spec.icon ~= nil then
            if type(spec.icon) == "string" then
                iconPath = spec.icon
            else
                logger:warn("ignoring invalid profession icon for", id)
            end
        end

        local ok, result = pcall(
            CharacterProfessionDefinition.addCharacterProfessionDefinition,
            profession,
            spec.name,
            math.floor(tonumber(spec.cost) or 0),
            description,
            iconPath
        )
        if not ok then
            logger:error("failed to create profession definition", id, ":", tostring(result))
            return nil, "character profession definition failed"
        end
        definition = result
        createdDefinition = true
    end

    local entry = setmetatable({
        id                 = id,
        type               = profession,
        definition         = definition,
        spec               = spec,
        _createdDefinition = createdDefinition,
    }, PallidProfession)

    registry[id] = entry
    registrationOrder[#registrationOrder + 1] = entry

    if createdDefinition then
        -- A pre-existing script definition is intentionally left untouched.
        applySpec(entry)
    end

    resolveGrantedTraits()
    logger:info("registered profession", id)
    return entry
end

--- Returns a profession registered through Pallid.Professions.
---@param id string Registry id.
---@return PallidProfession|nil profession Registered wrapper or nil.
function Professions.get(id)
    if type(id) ~= "string" then
        return nil
    end
    return registry[normalizeId(id)]
end

--- Returns whether a profession was registered through Pallid.Professions.
---@param id string Registry id.
---@return boolean registered True when the profession is known to this module.
function Professions.isRegistered(id)
    return type(id) == "string" and registry[normalizeId(id)] ~= nil
end

--- Returns the native CharacterProfession object.
---@return CharacterProfession profession Native profession registry object.
function PallidProfession:getType()
    return self.type
end

--- Returns the native CharacterProfessionDefinition object.
---@return CharacterProfessionDefinition definition Native profession definition.
function PallidProfession:getDefinition()
    return self.definition
end

Professions.PallidProfession = PallidProfession

--- Resolve late granted-trait references before the character creation screen
--- is used. Vanilla registers its own OnGameBoot handler first, so a profession
--- description may be generated before this pass; the granted trait itself is
--- still applied when the profession is selected.
Events.OnGameBoot.Add(resolveGrantedTraits)

return Pallid
