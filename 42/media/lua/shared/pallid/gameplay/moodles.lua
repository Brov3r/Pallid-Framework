require "utils/logger"

Pallid = Pallid or {}
Pallid.Moodles = Pallid.Moodles or {}

local Moodles = Pallid.Moodles
local logger = Pallid.getLogger("Moodles")

--- Network module name used by the moodle state commands.
Moodles._NET_MODULE = "Pallid_Moodles"

--- Command sent by a client to change one of its own moodle values.
Moodles._NET_SET = "Pallid_set"

--- Command sent by a client to request all of its moodle values.
Moodles._NET_REQUEST = "Pallid_request"

--- Command sent by the server with authoritative moodle values.
Moodles._NET_STATE = "Pallid_state"

--- Neutral value; a moodle at this value is not displayed.
local NEUTRAL_VALUE = 0.5

--- ModData key that owns all custom moodle values.
local MOD_DATA_KEY = "Pallid_Moodles"

--- Default thresholds copied into every definition.
---@type table<string, number>
local DEFAULT_THRESHOLDS = {
    bad4  = 0.1,
    bad3  = 0.2,
    bad2  = 0.3,
    bad1  = 0.4,
    good1 = 0.6,
    good2 = 0.7,
    good3 = 0.8,
    good4 = 0.9,
}

--- Definition accepted by Pallid.Moodles.add.
---@class PallidMoodleSpec
---@field id string Unique id with a namespace, e.g. "mymod:stress".
---@field icon string Texture path for the moodle icon; required.
---@field title string|table|nil Display title, or a table keyed by "good"/"bad" and level 1..4.
---@field description string|table|nil Tooltip description, or a table keyed by "good"/"bad" and level 1..4.
---@field icons table|nil Optional per-alignment/per-level texture overrides.
---@field thresholds table|nil Partial threshold overrides merged with the defaults.
---@field priority number|nil Drawing order; lower values are drawn first.
---@field draw boolean|nil When false the built-in renderer skips this moodle.

--- Registered moodle definition returned by Pallid.Moodles.add.
---@class PallidMoodle
---@field id string Normalized registry id.
---@field spec PallidMoodleSpec The spec used to register the moodle.
---@field icon string Icon texture path.
---@field icons table|nil Optional per-alignment/per-level texture overrides.
---@field title string|table|nil Display title.
---@field description string|table|nil Tooltip description.
---@field thresholds table<string, number> Instance-owned thresholds.
---@field priority number Drawing order.
---@field draw boolean Whether the built-in renderer draws this moodle.
local PallidMoodle = {}
PallidMoodle.__index = PallidMoodle

--- Registered moodles keyed by normalized id.
---@type table<string, PallidMoodle>
Moodles._definitions = {}

--- Registered moodles sorted by priority and registration order.
---@type PallidMoodle[]
Moodles._order = {}

--- Returns the lower-case registry id used by ResourceLocation.
---@param id string Moodle id.
---@return string normalized Normalized id.
local function normalizeId(id)
    return string.lower(tostring(id))
end

--- Clamps a moodle value to the supported range.
---@param value any Value converted to a number when possible.
---@return number clamped Value in the range 0..1.
local function clampValue(value)
    local number = tonumber(value)
    if number == nil or number ~= number then
        return NEUTRAL_VALUE
    end
    if number < 0 then
        return 0
    end
    if number > 1 then
        return 1
    end
    return number
end

--- Returns true when two moodle values are effectively equal.
---@param left number First value.
---@param right number Second value.
---@return boolean equal True when the values differ by less than 1e-6.
local function valuesEqual(left, right)
    return math.abs(left - right) < 1e-6
end

--- Returns the ModData table of a player, or nil when the player is invalid.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return table|nil modData Player ModData table.
local function getModData(player)
    if player == nil or player.getModData == nil then
        return nil
    end

    local ok, data = pcall(player.getModData, player)
    if not ok then
        return nil
    end
    return data
end

--- Returns the moodle values table of a player.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@param create boolean|nil Create the table when it is missing.
---@return table|nil values Player-owned moodle values.
local function getValues(player, create)
    local data = getModData(player)
    if data == nil then
        return nil
    end

    local values = data[MOD_DATA_KEY]
    if type(values) ~= "table" then
        if not create then
            return nil
        end
        values = {}
        data[MOD_DATA_KEY] = values
    end
    return values
end

--- Writes a numeric moodle value into a player's ModData.
---@param player IsoGameCharacter|IsoPlayer Character to modify.
---@param id string Normalized moodle id.
---@param value number Clamped value.
---@return boolean applied True when the value was written.
function Moodles._applyValue(player, id, value)
    local values = getValues(player, true)
    if values == nil then
        return false
    end
    values[id] = clampValue(value)
    return true
end

--- Applies a table of authoritative values to a player.
---@param player IsoGameCharacter|IsoPlayer Character to modify.
---@param values table|nil Map of moodle id to value.
---@return boolean applied True when at least one registered value was applied.
function Moodles._applyValues(player, values)
    if type(values) ~= "table" then
        return false
    end

    local target = getValues(player, true)
    if target == nil then
        return false
    end

    local applied = false
    for i = 1, #Moodles._order do
        local definition = Moodles._order[i]
        local value = values[definition.id]
        if value ~= nil then
            target[definition.id] = clampValue(value)
            applied = true
        end
    end
    return applied
end

--- Collects all registered moodle values of a player.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return table<string, number> values Map of moodle id to value.
function Moodles._collectValues(player)
    local result = {}
    local values = getValues(player, false)
    for i = 1, #Moodles._order do
        local definition = Moodles._order[i]
        result[definition.id] = clampValue(values ~= nil and values[definition.id] or NEUTRAL_VALUE)
    end
    return result
end

--- Sends authoritative values to the owning client.
---@param player IsoPlayer Player receiving the update.
---@param values table<string, number> values Changed values.
function Moodles._sendState(player, values)
    if not isServer() or player == nil or not instanceof(player, "IsoPlayer") then
        return
    end

    local ok, err = pcall(sendServerCommand, player, Moodles._NET_MODULE, Moodles._NET_STATE, {
        onlineID = player:getOnlineID(),
        values   = values,
    })
    if not ok then
        logger:error("failed to send moodle state:", tostring(err))
    end
end

--- Inserts a definition into the priority-sorted order.
---@param definition PallidMoodle Definition to insert.
local function insertOrdered(definition)
    local order = Moodles._order
    local index = #order + 1

    for i = 1, #order do
        local other = order[i]
        if definition.priority < other.priority then
            index = i
            break
        end
    end

    table.insert(order, index, definition)
end

--- Resolves a title/description value for an alignment and level.
---@param value string|table|nil Configured value.
---@param alignment number 0 neutral, 1 good, 2 bad.
---@param level number Moodle level 1..4.
---@param fallback string Value used when nothing is configured.
---@return string text Resolved text.
local function resolveText(value, alignment, level, fallback)
    if type(value) == "string" then
        return value
    end

    if type(value) == "table" then
        local key = nil
        if alignment == 1 then
            key = "good"
        elseif alignment == 2 then
            key = "bad"
        end

        local group = key ~= nil and value[key] or nil
        if type(group) == "table" then
            local text = group[level]
            if text ~= nil then
                return tostring(text)
            end
        end
    end

    return fallback
end

--- Adds a moodle definition.
---
--- Definitions are loaded on both client and server. The icon is required so
--- the client renderer never has to guess a fallback texture.
---
--- @param spec PallidMoodleSpec Moodle definition.
--- @return PallidMoodle|nil moodle Registered definition, or nil when invalid.
--- @return string|nil error Description of the validation failure.
function Moodles.add(spec)
    if type(spec) ~= "table" then
        logger:error("Pallid.Moodles.add expects a definition table")
        return nil, "definition table expected"
    end

    if type(spec.id) ~= "string" or spec.id == "" then
        logger:error("Pallid.Moodles.add requires a non-empty id")
        return nil, "id required"
    end

    if string.match(spec.id, "^[^:]+:.+$") == nil then
        logger:error("moodle id must include a namespace and a path:", tostring(spec.id))
        return nil, "invalid id"
    end

    if type(spec.icon) ~= "string" or spec.icon == "" then
        logger:error("Pallid.Moodles.add requires a non-empty icon for", spec.id)
        return nil, "icon required"
    end

    local id = normalizeId(spec.id)
    if Moodles._definitions[id] ~= nil then
        logger:error("moodle already registered:", id)
        return nil, "duplicate id"
    end

    local thresholds = {}
    for key, value in pairs(DEFAULT_THRESHOLDS) do
        thresholds[key] = value
    end
    if type(spec.thresholds) == "table" then
        for key, value in pairs(spec.thresholds) do
            local number = tonumber(value)
            if number ~= nil then
                thresholds[key] = number
            end
        end
    end

    local priority = tonumber(spec.priority)
    if priority == nil or priority ~= priority then
        priority = 0
    end

    local definition = setmetatable({
        id          = id,
        spec        = spec,
        icon        = spec.icon,
        icons       = spec.icons,
        title       = spec.title,
        description = spec.description,
        thresholds  = thresholds,
        priority    = priority,
        draw        = spec.draw ~= false,
    }, PallidMoodle)

    Moodles._definitions[id] = definition
    insertOrdered(definition)

    logger:info("registered moodle", id)
    return definition
end

--- Returns a registered moodle definition.
---@param id string Moodle id.
---@return PallidMoodle|nil moodle Registered definition or nil.
function Moodles.get(id)
    if type(id) ~= "string" then
        return nil
    end
    return Moodles._definitions[normalizeId(id)]
end

--- Returns whether a moodle id was registered.
---@param id string Moodle id.
---@return boolean registered True when the moodle is known.
function Moodles.isRegistered(id)
    return type(id) == "string" and Moodles._definitions[normalizeId(id)] ~= nil
end

--- Returns a moodle value for a player.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@param id string|PallidMoodle Moodle id or definition.
---@return number value Value in the range 0..1; 0.5 when unset.
function Moodles.getValue(player, id)
    local definition = type(id) == "string" and Moodles.get(id) or id
    if definition == nil then
        return NEUTRAL_VALUE
    end

    local values = getValues(player, false)
    if values == nil then
        return NEUTRAL_VALUE
    end

    return clampValue(values[definition.id])
end

--- Sets a moodle value for a player.
---
--- In singleplayer the value is written locally. On a server it is written and
--- sent to the owning client. On a multiplayer client the value is written
--- optimistically and the server is asked to confirm it.
---
--- @param player IsoGameCharacter|IsoPlayer Character to modify.
--- @param id string|PallidMoodle Moodle id or definition.
--- @param value number New value in the range 0..1.
--- @return boolean changed True when a network update or local write happened.
function Moodles.setValue(player, id, value)
    local definition = type(id) == "string" and Moodles.get(id) or id
    if definition == nil then
        logger:error("cannot set an unregistered moodle:", tostring(id))
        return false
    end

    if player == nil then
        logger:error("cannot set moodle", definition.id, "without a player")
        return false
    end

    if not isServer() and isClient() and instanceof(player, "IsoPlayer")
        and not player:isLocalPlayer() then
        logger:warn("ignored moodle update for a remote player on a client:", definition.id)
        return false
    end

    local clamped = clampValue(value)
    local current = Moodles.getValue(player, definition)
    if valuesEqual(current, clamped) then
        return false
    end

    if not Moodles._applyValue(player, definition.id, clamped) then
        return false
    end

    if isServer() then
        Moodles._sendState(player, { [definition.id] = clamped })
    elseif isClient() and instanceof(player, "IsoPlayer") then
        local ok, err = pcall(sendClientCommand, player, Moodles._NET_MODULE, Moodles._NET_SET, {
            id    = definition.id,
            value = clamped,
        })
        if not ok then
            logger:error("failed to send moodle update:", tostring(err))
        end
    end

    return true
end

--- Returns the level derived from a moodle value.
---@param definition PallidMoodle Moodle definition.
---@param value number Value in the range 0..1.
---@return number level Level in the range 0..4.
function Moodles._levelForValue(definition, value)
    if valuesEqual(value, NEUTRAL_VALUE) then
        return 0
    end

    local thresholds = definition.thresholds
    if value <= thresholds.bad4 or value >= thresholds.good4 then
        return 4
    end
    if value <= thresholds.bad3 or value >= thresholds.good3 then
        return 3
    end
    if value <= thresholds.bad2 or value >= thresholds.good2 then
        return 2
    end
    if value <= thresholds.bad1 or value >= thresholds.good1 then
        return 1
    end
    return 0
end

--- Returns the alignment derived from a moodle value.
---@param value number Value in the range 0..1.
---@return number alignment 0 neutral, 1 good, 2 bad.
function Moodles._alignmentForValue(value)
    if value < NEUTRAL_VALUE then
        return 2
    end
    if value > NEUTRAL_VALUE then
        return 1
    end
    return 0
end

--- Returns the raw player-owned moodle value table for internal hot-path reads.
--- The returned table must not be modified or stored by callers.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return table|nil values Player-owned moodle values.
function Moodles._getValues(player)
    return getValues(player, false)
end

--- Clamps a value for internal hot-path reads.
---@param value any Value converted to a number when possible.
---@return number clamped Value in the range 0..1.
function Moodles._clampValue(value)
    return clampValue(value)
end

--- Returns the moodle level derived from its value.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@param id string|PallidMoodle Moodle id or definition.
---@return number level Level in the range 0..4.
function Moodles.getLevel(player, id)
    local definition = type(id) == "string" and Moodles.get(id) or id
    if definition == nil then
        return 0
    end

    local value = Moodles.getValue(player, definition)
    return Moodles._levelForValue(definition, value)
end

--- Returns the moodle alignment derived from its value.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@param id string|PallidMoodle Moodle id or definition.
---@return number alignment 0 neutral, 1 good, 2 bad.
function Moodles.getAlignment(player, id)
    local definition = type(id) == "string" and Moodles.get(id) or id
    if definition == nil then
        return 0
    end

    local value = Moodles.getValue(player, definition)
    return Moodles._alignmentForValue(value)
end

--- Resets a moodle to its neutral value.
---@param player IsoGameCharacter|IsoPlayer Character to modify.
---@param id string|PallidMoodle Moodle id or definition.
---@return boolean changed True when the value changed.
function Moodles.clear(player, id)
    return Moodles.setValue(player, id, NEUTRAL_VALUE)
end

--- Returns the resolved title for an alignment and level.
---@param alignment number 0 neutral, 1 good, 2 bad.
---@param level number Moodle level 1..4.
---@return string title Resolved title.
function PallidMoodle:getTitle(alignment, level)
    return resolveText(self.title, alignment, level, self.id)
end

--- Returns the resolved description for an alignment and level.
---@param alignment number 0 neutral, 1 good, 2 bad.
---@param level number Moodle level 1..4.
---@return string description Resolved description.
function PallidMoodle:getDescription(alignment, level)
    return resolveText(self.description, alignment, level, "")
end

--- Returns the icon path for an alignment and level.
---@param alignment number 0 neutral, 1 good, 2 bad.
---@param level number Moodle level 1..4.
---@return string path Resolved icon path.
function PallidMoodle:getIconPath(alignment, level)
    local key = nil
    if alignment == 1 then
        key = "good"
    elseif alignment == 2 then
        key = "bad"
    end

    if key ~= nil and type(self.icons) == "table" then
        local group = self.icons[key]
        if type(group) == "table" and group[level] ~= nil then
            return tostring(group[level])
        end
    end

    return self.icon
end

--- Sets this moodle's value for a player.
---@param player IsoGameCharacter|IsoPlayer Character to modify.
---@param value number New value in the range 0..1.
---@return boolean changed True when the value changed.
function PallidMoodle:setValue(player, value)
    return Moodles.setValue(player, self, value)
end

--- Returns this moodle's value for a player.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return number value Value in the range 0..1.
function PallidMoodle:getValue(player)
    return Moodles.getValue(player, self)
end

--- Returns this moodle's level for a player.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return number level Level in the range 0..4.
function PallidMoodle:getLevel(player)
    return Moodles.getLevel(player, self)
end

--- Returns this moodle's alignment for a player.
---@param player IsoGameCharacter|IsoPlayer Character to inspect.
---@return number alignment 0 neutral, 1 good, 2 bad.
function PallidMoodle:getAlignment(player)
    return Moodles.getAlignment(player, self)
end

--- Resets this moodle to its neutral value.
---@param player IsoGameCharacter|IsoPlayer Character to modify.
---@return boolean changed True when the value changed.
function PallidMoodle:clear(player)
    return Moodles.clear(player, self)
end

Moodles.PallidMoodle = PallidMoodle
Moodles.NEUTRAL_VALUE = NEUTRAL_VALUE

return Pallid
