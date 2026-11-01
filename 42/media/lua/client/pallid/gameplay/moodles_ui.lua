require "utils/logger"
require "pallid/gameplay/moodles"

Pallid = Pallid or {}

local Moodles = Pallid.Moodles
local Draw = require "pallid/gameplay/moodles_draw"
local logger = Pallid.getLogger("MoodlesUI")

--- Reused entry passed to readers of Pallid.Moodles.forEachVisible.
---@class PallidMoodleEntry
---@field id string Moodle id.
---@field definition PallidMoodle Registered moodle definition.
---@field value number Current value in the range 0..1.
---@field level number Current level in the range 0..4.
---@field alignment number 0 neutral, 1 good, 2 bad.
---@field texture Texture|nil Loaded icon texture; nil when the icon is missing.
---@field title string Resolved title.
---@field description string Resolved description.

--- Reused layout data passed to a custom renderer.
---@class PallidMoodleLayout
---@field playerNum number Zero-based local player index.
---@field element MoodlesUI|nil Native moodle element used as the drawing host.
---@field x number Absolute left coordinate of the native moodle column.
---@field y number Absolute top coordinate of the first custom moodle slot.
---@field firstY number Local top coordinate of the first custom moodle slot.
---@field size number Moodle size in pixels.
---@field spacing number Vertical distance between moodle slots.
---@field nativeCount number Number of visible native moodles above the custom list.
---@field screenLeft number Left coordinate of the player screen.
---@field screenTop number Top coordinate of the player screen.
---@field screenWidth number Width of the player screen.
---@field screenHeight number Height of the player screen.

--- Custom renderer contract.
---@class PallidMoodleRenderer
---@field render fun(self: PallidMoodleRenderer, element: MoodlesUI, player: IsoPlayer, entries: PallidMoodleEntry[], layout: PallidMoodleLayout)

--- Whether the built-in renderer draws custom moodles.
local rendererEnabled = true

--- Optional custom renderer replacing the built-in drawing function.
---@type PallidMoodleRenderer|function|nil
local customRenderer = nil

--- Cached native MoodleType objects.
---@type table[]|nil
local nativeTypes = nil

--- Set when a third-party MoodleType cannot be read from the native map.
local nativeCountFailed = false

--- Per-player hook state.
---@type table<number, table>
local hooks = {}

--- Per-player layout cache.
---@type table<number, PallidMoodleLayout>
local layouts = {}

--- Reused entries for the public forEachVisible helper.
---@type table[]
local scratchEntries = {}

--- Returns the zero-based player index of a character.
---@param player IsoGameCharacter|IsoPlayer|nil Character to inspect.
---@return number|nil playerNum Player index or nil.
local function getPlayerNum(player)
    if player == nil or player.getPlayerNum == nil then
        return nil
    end

    local ok, playerNum = pcall(player.getPlayerNum, player)
    if not ok then
        return nil
    end
    return playerNum
end

--- Returns the local player for a player index.
---@param playerNum number Zero-based player index.
---@param player IsoPlayer|nil Already known player.
---@return IsoPlayer|nil player Local player when available.
local function getPlayer(playerNum, player)
    if player ~= nil then
        return player
    end

    local ok, result = pcall(getSpecificPlayer, playerNum)
    if not ok then
        return nil
    end
    return result
end

--- Builds the native MoodleType list once.
---@return table[] types Native moodle types.
local function getNativeTypes()
    if nativeTypes ~= nil then
        return nativeTypes
    end

    nativeTypes = {}
    local ok, list = pcall(function()
        return Registries.MOODLE_TYPE:values()
    end)
    if not ok or list == nil then
        logger:error("failed to read native moodle types")
        return nativeTypes
    end

    for i = 0, list:size() - 1 do
        nativeTypes[#nativeTypes + 1] = list:get(i)
    end
    return nativeTypes
end

--- Counts the visible native moodle slots of a collection.
--- Mirrors MoodlesUI: FOOD_EATEN is only counted from the high level.
---@param moodles Moodles Native moodle collection.
---@param types table[] Native moodle types.
---@param foodEaten MoodleType|nil The FOOD_EATEN type.
---@return number count Number of visible native slots.
local function countNativeSlots(moodles, types, foodEaten)
    local count = 0

    for i = 1, #types do
        local moodleType = types[i]
        local level = moodles:getMoodleLevel(moodleType)
        if level > 0 then
            if moodleType == foodEaten and level < 3 then
                -- MoodlesUI hides FOOD_EATEN below HighMoodleLevel.
            else
                count = count + 1
            end
        end
    end

    return count
end

--- Counts native moodles currently displayed above the custom list.
---@param player IsoPlayer|nil Player to inspect.
---@return number count Number of visible native slots.
local function countNativeMoodles(player)
    if nativeCountFailed or player == nil or player.getMoodles == nil then
        return 0
    end

    local ok, moodles = pcall(player.getMoodles, player)
    if not ok or moodles == nil then
        return 0
    end

    local types = getNativeTypes()
    local foodEaten = MoodleType ~= nil and MoodleType.FOOD_EATEN or nil
    local counted, count = pcall(countNativeSlots, moodles, types, foodEaten)
    if not counted then
        nativeCountFailed = true
        logger:error("failed to count native moodles:", tostring(count))
        return 0
    end

    return count
end

--- Returns the cached layout state of a player.
---@param playerNum number Zero-based player index.
---@return PallidMoodleLayout layout Mutable layout state.
local function getLayoutState(playerNum)
    local layout = layouts[playerNum]
    if layout == nil then
        layout = {
            playerNum    = playerNum,
            element      = nil,
            x            = 0,
            y            = 0,
            firstY       = 0,
            size         = 32,
            spacing      = 42,
            nativeCount  = 0,
            screenLeft   = 0,
            screenTop    = 0,
            screenWidth  = 0,
            screenHeight = 0,
            lastMs       = 0,
        }
        layouts[playerNum] = layout
    end
    return layout
end

--- Refreshes the cached layout for a player.
---@param playerNum number Zero-based player index.
---@param player IsoPlayer|nil Player used for the native moodle count.
---@param force boolean|nil Recompute even when the cache is fresh.
---@param knownElement MoodlesUI|nil Element already known by the caller.
---@return PallidMoodleLayout layout Updated layout state.
local function updateLayout(playerNum, player, force, knownElement)
    local layout = getLayoutState(playerNum)
    local element = knownElement

    if element == nil then
        local ok, result = pcall(UIManager.getMoodleUI, playerNum)
        if ok then
            element = result
        end
    end

    local elementChanged = layout.element ~= element
    layout.element = element

    if element == nil then
        return layout
    end

    local now = getTimestampMs()
    if not force and not elementChanged and now - layout.lastMs < 250 then
        return layout
    end
    layout.lastMs = now

    local size = element:getWidth()
    layout.size = size
    layout.spacing = 10 + size
    layout.x = element:getAbsoluteX()
    layout.nativeCount = countNativeMoodles(player)
    layout.firstY = layout.nativeCount * layout.spacing
    layout.y = element:getAbsoluteY() + layout.firstY
    layout.screenLeft = getPlayerScreenLeft(playerNum)
    layout.screenTop = getPlayerScreenTop(playerNum)
    layout.screenWidth = getPlayerScreenWidth(playerNum)
    layout.screenHeight = getPlayerScreenHeight(playerNum)

    return layout
end

--- Builds the reusable visible-entry array of a hook.
---@param hook table Hook state.
---@param player IsoPlayer Player whose state is read.
---@return PallidMoodleEntry[] entries Reused entry array.
---@return number count Number of visible entries.
local function buildEntries(hook, player)
    local entries = hook.entries
    local values = Moodles._getValues(player)
    local count = 0

    for i = 1, #Moodles._order do
        local definition = Moodles._order[i]
        local value = Moodles._clampValue(values ~= nil and values[definition.id] or nil)
        local level = Moodles._levelForValue(definition, value)
        if level > 0 then
            count = count + 1
            local entry = entries[count]
            if entry == nil then
                entry = {}
                entries[count] = entry
            end
            Draw.fillEntry(entry, definition, value, level, Moodles._alignmentForValue(value))
        end
    end

    hook.entryCount = count
    return entries, count
end

--- Calls a callback stored on a previous Lua table without interrupting rendering.
---@param hook table Hook state.
---@param previous table|nil Previous Lua table.
---@param method string Method name to call.
---@param brokenField string Field used to remember a broken callback.
local function callPrevious(hook, previous, method, brokenField)
    if type(previous) ~= "table" or hook[brokenField] then
        return
    end

    local callback = previous[method]
    if type(callback) ~= "function" then
        return
    end

    local ok, err = pcall(callback, previous)
    if not ok then
        hook[brokenField] = true
        logger:error("previous MoodlesUI", method, "callback failed:", tostring(err))
    end
end

--- Renders custom moodles from the native MoodlesUI Lua callback.
---@param self table Installed Lua table.
local function renderHook(self)
    local hook = self.hook
    if hook == nil then
        return
    end

    callPrevious(hook, hook.previous, "render", "previousRenderBroken")

    if not rendererEnabled then
        return
    end

    local player = hook.player or getPlayer(hook.playerNum, nil)
    hook.player = player
    if player == nil or player:isDead() then
        return
    end

    local layout = updateLayout(hook.playerNum, player, false, self.element)
    if layout.element == nil then
        return
    end

    local entries, count = buildEntries(hook, player)
    if count == 0 then
        return
    end

    if customRenderer ~= nil then
        local ok, err
        if type(customRenderer) == "table" then
            ok, err = pcall(customRenderer.render, customRenderer, self.element, player, entries, layout)
        else
            ok, err = pcall(customRenderer, self.element, player, entries, layout)
        end

        if not ok then
            logger:error("custom moodle renderer failed, restoring the default renderer:", tostring(err))
            customRenderer = nil
            Draw.drawDefault(self.element, entries, count, layout)
        end
        return
    end

    Draw.drawDefault(self.element, entries, count, layout)
end

--- Updates cached layout from the native MoodlesUI Lua callback.
---@param self table Installed Lua table.
local function updateHook(self)
    local hook = self.hook
    if hook == nil then
        return
    end

    callPrevious(hook, hook.previous, "update", "previousUpdateBroken")

    local player = hook.player or getPlayer(hook.playerNum, nil)
    hook.player = player
    if player ~= nil then
        updateLayout(hook.playerNum, player, false, self.element)
    end
end

--- Restores the previous Lua table of a native MoodlesUI element.
---@param playerNum number Zero-based player index.
local function removeHook(playerNum)
    local hook = hooks[playerNum]
    if hook == nil then
        return
    end

    local element = hook.element
    local current = nil
    if element ~= nil then
        local ok, value = pcall(element.getTable, element)
        if ok then
            current = value
        end
    end

    if element ~= nil and hook.table ~= nil
        and (current == hook.table or (current ~= nil and current._pallidHook == hook)) then
        local ok, err = pcall(element.setTable, element, hook.previous)
        if not ok then
            logger:error("failed to restore the previous MoodlesUI table:", tostring(err))
        end
    end

    hooks[playerNum] = nil
end

--- Installs the Lua callback table into a player's native MoodlesUI.
---@param playerNum number Zero-based player index.
---@param player IsoPlayer|nil Player associated with the element.
---@return table|nil hook Installed hook state.
local function installHook(playerNum, player)
    if not rendererEnabled then
        return nil
    end

    local ok, element = pcall(UIManager.getMoodleUI, playerNum)
    if not ok or element == nil then
        return nil
    end

    local previous = element:getTable()
    local installed = setmetatable({
        playerNum = playerNum,
        element   = element,
        previous  = previous,
        player    = getPlayer(playerNum, player),
    }, {
        -- Keep every other Lua callback of the previous table reachable
        -- through UIElement's normal table lookup (prerender, mouse handlers,
        -- onResize and similar).
        __index = previous,
    })
    installed.render = function(self)
        renderHook(self)
    end
    installed.update = function(self)
        updateHook(self)
    end

    local hook = {
        playerNum            = playerNum,
        element              = element,
        player               = installed.player,
        previous             = previous,
        previousRenderBroken = false,
        previousUpdateBroken = false,
        table                = installed,
        entries              = {},
        entryCount           = 0,
    }
    installed.hook = hook
    installed._pallidHook = hook

    local okSet, err = pcall(element.setTable, element, installed)
    if not okSet then
        logger:error("failed to attach the moodle renderer:", tostring(err))
        return nil
    end

    hooks[playerNum] = hook
    logger:info("attached moodle renderer to player", playerNum)
    return hook
end

--- Ensures the renderer is attached to the current MoodlesUI of a player.
---@param playerNum number Zero-based player index.
---@param player IsoPlayer|nil Player associated with the element.
---@return table|nil hook Active hook state.
local function ensureHooked(playerNum, player)
    if not rendererEnabled or playerNum == nil then
        return nil
    end

    local ok, element = pcall(UIManager.getMoodleUI, playerNum)
    if not ok or element == nil then
        return nil
    end

    local hook = hooks[playerNum]
    if hook ~= nil and hook.element == element and hook.table ~= nil then
        local okTable, current = pcall(element.getTable, element)
        if okTable and (current == hook.table
            or (current ~= nil and current._pallidHook == hook)) then
            hook.player = getPlayer(playerNum, player)
            return hook
        end
    end

    return installHook(playerNum, player)
end

--- Enables or disables the built-in custom moodle renderer.
---
--- Disabling restores the Lua table that was present in MoodlesUI before the
--- framework attached its callback. State and multiplayer synchronisation keep
--- working, so a mod can draw the moodles with its own widget.
---
--- @param enabled boolean|nil False disables rendering; any other value enables it.
function Moodles.setRendererEnabled(enabled)
    local value = enabled ~= false
    if rendererEnabled == value then
        return
    end

    rendererEnabled = value

    if not value then
        for playerNum in pairs(hooks) do
            removeHook(playerNum)
        end
        return
    end

    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            ensureHooked(player:getPlayerNum(), player)
        end
    end
end

--- Returns whether the built-in custom moodle renderer is enabled.
---@return boolean enabled True when the built-in renderer draws moodles.
function Moodles.isRendererEnabled()
    return rendererEnabled
end

--- Installs a custom renderer or restores the built-in one.
---
--- The renderer receives the native MoodlesUI element, the local player, the
--- reusable visible entry array and the reusable layout table. Entries and the
--- layout are reused between frames and must not be stored or modified.
---
--- @param renderer PallidMoodleRenderer|function|nil Renderer table with render(), render function, or nil for the built-in renderer.
--- @return boolean accepted True when the renderer was accepted.
function Moodles.setRenderer(renderer)
    if renderer == nil then
        customRenderer = nil
        return true
    end

    if type(renderer) == "function"
        or (type(renderer) == "table" and type(renderer.render) == "function") then
        customRenderer = renderer
        return true
    end

    logger:error("Pallid.Moodles.setRenderer expects a function, a table with render(), or nil")
    return false
end

--- Returns the cached layout of custom moodles for a player.
---@param player IsoPlayer Player whose layout is requested.
---@return number|nil x Absolute left coordinate of the native moodle column.
---@return number|nil y Absolute top coordinate of the first custom moodle slot.
---@return number|nil size Moodle size in pixels.
---@return number|nil spacing Vertical distance between moodle slots.
---@return number|nil nativeCount Number of visible native moodles.
function Moodles.getLayout(player)
    local playerNum = getPlayerNum(player)
    if playerNum == nil then
        return nil
    end

    local layout = updateLayout(playerNum, player, false)
    if layout.element == nil then
        return nil
    end

    return layout.x, layout.y, layout.size, layout.spacing, layout.nativeCount
end

--- Iterates visible custom moodles without allocating a new table per entry.
---
--- The entry passed to the callback is reused between calls and must not be
--- stored or modified.
---
--- @param player IsoPlayer Player whose moodles are iterated.
--- @param callback fun(entry: PallidMoodleEntry) Callback invoked for each visible moodle.
--- @return number count Number of visible moodles.
function Moodles.forEachVisible(player, callback)
    if type(callback) ~= "function" then
        return 0
    end

    local values = Moodles._getValues(player)
    local count = 0

    for i = 1, #Moodles._order do
        local definition = Moodles._order[i]
        local value = Moodles._clampValue(values ~= nil and values[definition.id] or nil)
        local level = Moodles._levelForValue(definition, value)
        if level > 0 then
            count = count + 1
            local entry = scratchEntries[count]
            if entry == nil then
                entry = {}
                scratchEntries[count] = entry
            end
            Draw.fillEntry(entry, definition, value, level, Moodles._alignmentForValue(value))
            callback(entry)
        end
    end

    return count
end

--- Attaches the renderer as soon as the native moodle elements exist.
Events.OnCreateUI.Add(function()
    for i = 0, 3 do
        ensureHooked(i, nil)
    end
end)

--- Attaches the renderer when a local player loads.
Events.OnCreatePlayer.Add(function(playerNum, player)
    local index = player ~= nil and getPlayerNum(player) or playerNum
    if index ~= nil then
        ensureHooked(index, player)
    end
end)

--- Attaches the renderer after the world finishes loading.
Events.OnGameStart.Add(function()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            ensureHooked(player:getPlayerNum(), player)
        end
    end
end)

--- Invalidates cached layout when the window is resized.
Events.OnResolutionChange.Add(function()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            local playerNum = player:getPlayerNum()
            updateLayout(playerNum, player, true)
            ensureHooked(playerNum, player)
        end
    end
end)

--- Stops drawing custom moodles for a dead player until a new character loads.
Events.OnPlayerDeath.Add(function(player)
    local playerNum = getPlayerNum(player)
    if playerNum == nil then
        return
    end

    local hook = hooks[playerNum]
    if hook ~= nil then
        hook.player = nil
        hook.entryCount = 0
    end
end)

--- Re-attaches after IsoCamera replaces the native MoodlesUI element.
--- The check is throttled to roughly once per second to keep this per-tick
--- handler cheap.
local ensureCounter = 0
Events.OnPlayerUpdate.Add(function(player)
    ensureCounter = ensureCounter + 1
    if ensureCounter < 60 then
        return
    end

    ensureCounter = 0
    local playerNum = getPlayerNum(player)
    if playerNum ~= nil then
        ensureHooked(playerNum, player)
    end
end)

return Pallid
