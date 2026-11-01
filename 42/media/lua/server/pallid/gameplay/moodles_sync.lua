require "utils/logger"
require "pallid/gameplay/moodles"

Pallid = Pallid or {}

local Moodles = Pallid.Moodles
local logger = Pallid.getLogger("MoodlesSync")

-- The server Lua directory is loaded on multiplayer clients too. Register the
-- handlers only where server commands are actually dispatched.
if not Pallid.Net.isAuthority() then
    return Pallid
end

--- Minimum interval between repeated moodle rejection log lines.
local REJECT_LOG_INTERVAL_MS = 5000

--- Maximum number of characters kept from a rejected moodle id.
local REJECT_ID_LIMIT = 64

--- Timestamp of the last unknown-id warning.
local lastUnknownIdWarnMs = 0

--- Timestamp of the last server-owned moodle warning.
local lastServerOwnedWarnMs = 0

--- Truncates and escapes a client-supplied id before logging it.
---@param id string Moodle id received from a client.
---@return string text Safe log text.
local function sanitizeId(id)
    local text = tostring(id)
    if #text > REJECT_ID_LIMIT then
        text = string.sub(text, 1, REJECT_ID_LIMIT) .. "..."
    end
    return (string.gsub(text, "%c", "?"))
end

--- Logs an unknown moodle id with throttling.
---@param id string Rejected moodle id.
local function warnUnknownId(id)
    local now = getTimestampMs()
    if now - lastUnknownIdWarnMs < REJECT_LOG_INTERVAL_MS then
        return
    end

    lastUnknownIdWarnMs = now
    logger:warn("ignored moodle update for unknown id:", sanitizeId(id))
end

--- Logs a client attempt to set a server-owned moodle with throttling.
---@param id string Rejected moodle id.
local function warnServerOwned(id)
    local now = getTimestampMs()
    if now - lastServerOwnedWarnMs < REJECT_LOG_INTERVAL_MS then
        return
    end

    lastServerOwnedWarnMs = now
    logger:warn("ignored client update for a server-owned moodle:", sanitizeId(id))
end

--- Answers a client request with the full authoritative moodle state.
---
--- The limit mirrors the previous moodle budget: 20 commands per 10 seconds.
Pallid.Net.onServer(Moodles._ACTION_REQUEST, {
    limit = {
        max    = 20,
        window = 10000,
    },
}, function(player)
    if player == nil then
        return
    end

    Moodles._sendState(player, Moodles._collectValues(player))
end)

--- Applies a client moodle update and echoes the clamped value back.
---
--- Only moodles registered with `clientWritable = true` accept client writes;
--- gameplay-relevant moodles stay server-authoritative by default.
Pallid.Net.onServer(Moodles._ACTION_SET, {
    limit  = {
        max    = 20,
        window = 10000,
    },
    schema = {
        id    = {
            type      = "string",
            maxLength = 256,
        },
        value = "number",
    },
}, function(player, payload)
    if player == nil then
        return
    end

    local definition = Moodles.get(payload.id)
    if definition == nil then
        warnUnknownId(payload.id)
        return
    end

    if not definition.clientWritable then
        warnServerOwned(payload.id)
        return
    end

    -- Second-level defence: the schema only checks the type, while the
    -- gameplay layer keeps values inside 0..1.
    local value = Moodles._clampValue(payload.value)
    if not Moodles._applyValue(player, definition.id, value) then
        logger:warn("failed to apply moodle:", sanitizeId(definition.id))
        return
    end

    Moodles._sendState(player, { [definition.id] = value })
end)

return Pallid
