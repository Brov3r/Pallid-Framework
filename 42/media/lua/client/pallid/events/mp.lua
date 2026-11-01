require "utils/logger"
require "pallid/events/core"

Pallid = Pallid or {}

--- Event emitted when the client's online player list changes.
--- Parameters: added names, removed names and the full current list.
local EVENT_CHANGED = "Pallid_OnlinePlayersChanged"

--- Online player tracking for multiplayer clients.
---
--- The engine does not expose a Lua event for a player joining or leaving, but
--- the client receives the full scoreboard list. The module keeps the previous
--- snapshot and reports the difference.
---
--- Side: client.
local internal = Pallid.Events._internal
internal.mp = internal.mp or {}

if not internal.mp.installed then
    Pallid.Events.ensure(EVENT_CHANGED)

    --- Copies a Java list of user names into a Lua array.
    ---@param list ArrayList|nil Java list supplied by the engine.
    ---@return table names Lua array of user names.
    local function collect(list)
        local names = {}
        if list == nil then
            return names
        end

        for index = 1, list:size() do
            names[index] = list:get(index - 1)
        end

        return names
    end

    --- Compares the new list with the previous one and reports the difference.
    ---@param usernames ArrayList|nil User names supplied by the scoreboard event.
    local function onScoreboardUpdate(usernames)
        local current = collect(usernames)
        local currentSet = {}
        local added = {}
        local removed = {}

        for index = 1, #current do
            local name = current[index]
            currentSet[name] = true

            if internal.mp.previous == nil or not internal.mp.previous[name] then
                added[#added + 1] = name
            end
        end

        if internal.mp.previous ~= nil then
            for name in pairs(internal.mp.previous) do
                if not currentSet[name] then
                    removed[#removed + 1] = name
                end
            end
        end

        internal.mp.previous = currentSet
        Pallid.Events.emit(EVENT_CHANGED, added, removed, current)
    end

    --- Clears the cached list so a new connection starts from scratch.
    local function onDisconnect()
        internal.mp.previous = nil
    end

    Pallid.Events.add("OnScoreboardUpdate", onScoreboardUpdate)
    Pallid.Events.add("OnDisconnect", onDisconnect)

    internal.mp.installed = true
end

return Pallid
