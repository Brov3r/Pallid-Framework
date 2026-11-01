require "utils/logger"
require "pallid/gameplay/moodles"

Pallid = Pallid or {}

local Moodles = Pallid.Moodles
local logger = Pallid.getLogger("MoodlesSync")

--- Maximum number of moodle commands accepted from one player per window.
local MAX_REQUESTS = 20

--- Request window length in milliseconds.
local REQUEST_WINDOW_MS = 10000

--- Per-player rate-limit state keyed by online id.
---@type table<number, table>
local requestWindows = {}

--- Returns whether a player may send another moodle command.
---@param player IsoPlayer Player sending the command.
---@return boolean allowed True when the request is inside the rate limit.
local function allowRequest(player)
    local onlineID = player:getOnlineID()
    if onlineID == nil then
        return true
    end

    local now = getTimestampMs()
    local window = requestWindows[onlineID]

    if window == nil or now - window.startedAt >= REQUEST_WINDOW_MS then
        requestWindows[onlineID] = { startedAt = now, count = 1 }
        return true
    end

    window.count = window.count + 1
    return window.count <= MAX_REQUESTS
end

--- Handles a moodle state request from a client.
---@param player IsoPlayer Requesting player.
local function handleRequest(player)
    Moodles._sendState(player, Moodles._collectValues(player))
end

--- Handles a client request to change one of its own moodle values.
---@param player IsoPlayer Requesting player.
---@param args table|nil Command arguments.
local function handleSet(player, args)
    if type(args) ~= "table" or type(args.id) ~= "string" then
        return
    end

    local definition = Moodles.get(args.id)
    if definition == nil then
        logger:warn("ignored moodle update for unknown id:", tostring(args.id))
        return
    end

    local value = Moodles._clampValue(args.value)
    Moodles._applyValue(player, definition.id, value)
    Moodles._sendState(player, { [definition.id] = value })
end

--- Receives validated moodle commands from clients.
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Moodles._NET_MODULE or player == nil then
        return
    end

    if command ~= Moodles._NET_REQUEST and command ~= Moodles._NET_SET then
        return
    end

    if not allowRequest(player) then
        logger:warn("rate-limited moodle command from", tostring(player:getUsername()))
        Moodles._sendState(player, Moodles._collectValues(player))
        return
    end

    if command == Moodles._NET_REQUEST then
        handleRequest(player)
    else
        handleSet(player, args)
    end
end)

return Pallid
