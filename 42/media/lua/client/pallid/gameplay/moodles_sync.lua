require "utils/logger"
require "pallid/gameplay/moodles"

Pallid = Pallid or {}

local Moodles = Pallid.Moodles
local logger = Pallid.getLogger("MoodlesSync")

--- Finds the local player matching a server player id.
---@param onlineID number|nil Online id sent by the server.
---@return IsoPlayer|nil player Matching local player.
local function findLocalPlayer(onlineID)
    local target = tonumber(onlineID)
    if target == nil then
        return nil
    end

    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil and player:getOnlineID() == target then
            return player
        end
    end

    return nil
end

--- Requests the authoritative moodle state of a local player.
---@param player IsoPlayer Local player.
local function requestState(player)
    local ok, err = pcall(sendClientCommand, player, Moodles._NET_MODULE, Moodles._NET_REQUEST, {})
    if not ok then
        logger:error("failed to request moodle state:", tostring(err))
    end
end

--- Applies authoritative moodle values received from the server.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= Moodles._NET_MODULE or command ~= Moodles._NET_STATE then
        return
    end

    if type(args) ~= "table" or type(args.values) ~= "table" then
        return
    end

    local player = findLocalPlayer(args.onlineID)
    if player == nil then
        return
    end

    Moodles._applyValues(player, args.values)
end)

--- Requests the current state when a local player loads.
Events.OnCreatePlayer.Add(function(playerNum, player)
    if isClient() and player ~= nil then
        requestState(player)
    end
end)

--- Requests the current state again after the world finishes loading.
Events.OnGameStart.Add(function()
    if not isClient() then
        return
    end

    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            requestState(player)
        end
    end
end)

return Pallid
