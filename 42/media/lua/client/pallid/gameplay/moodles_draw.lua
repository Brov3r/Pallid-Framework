require "utils/logger"
require "pallid/ui/api/textures"

Pallid = Pallid or {}

local Textures = Pallid.UI.Textures

--- Drawing helpers shared by the built-in custom moodle renderer.
---@class PallidMoodlesDraw
local Draw = {}

--- Background texture cache keyed by moodle size.
---@type table<number, Texture|false> Background textures by size; false caches a failed load.
local backgroundCache = {}

--- Border texture cache keyed by moodle size.
---@type table<number, Texture|false> Border textures by size; false caches a failed load.
local borderCache = {}

--- Loads and caches a native moodle background texture.
---@param size number Moodle size in pixels.
---@return Texture|nil texture Background texture.
local function getBackground(size)
    local cached = backgroundCache[size]
    if cached ~= nil then
        return cached or nil
    end

    local path = "media/ui/Moodles/" .. tostring(math.floor(size)) .. "/_Moodles_BGsolid.png"
    local texture = Textures.get(path)
    if texture == nil then
        backgroundCache[size] = false
        return nil
    end

    backgroundCache[size] = texture
    return texture
end

--- Loads and caches a native moodle border texture.
---@param size number Moodle size in pixels.
---@return Texture|nil texture Border texture.
local function getBorder(size)
    local cached = borderCache[size]
    if cached ~= nil then
        return cached or nil
    end

    local path = "media/ui/Moodles/" .. tostring(math.floor(size)) .. "/_Moodles_BGoutline.png"
    local texture = Textures.get(path)
    if texture == nil then
        borderCache[size] = false
        return nil
    end

    borderCache[size] = texture
    return texture
end

--- Fills a reusable entry from the current moodle state.
---@param entry PallidMoodleEntry Reused entry table.
---@param definition PallidMoodle Moodle definition.
---@param value number Current value.
---@param level number Current level.
---@param alignment number Current alignment.
function Draw.fillEntry(entry, definition, value, level, alignment)
    if entry.definition ~= definition then
        entry.definition = definition
        entry.cachedLevel = nil
        entry.cachedAlignment = nil
    end

    entry.id = definition.id
    entry.value = value
    entry.level = level
    entry.alignment = alignment

    if entry.cachedLevel ~= level or entry.cachedAlignment ~= alignment then
        entry.cachedLevel = level
        entry.cachedAlignment = alignment
        entry.title = definition:getTitle(alignment, level)
        entry.description = definition:getDescription(alignment, level)
        entry.texture = Textures.get(definition:getIconPath(alignment, level))
    end
end

--- Returns a colour channel for a moodle alignment and level.
---@param alignment number 0 neutral, 1 good, 2 bad.
---@param level number Moodle level 1..4.
---@param goodR number Good highlight red channel.
---@param goodG number Good highlight green channel.
---@param goodB number Good highlight blue channel.
---@param badR number Bad highlight red channel.
---@param badG number Bad highlight green channel.
---@param badB number Bad highlight blue channel.
---@return number r Red channel.
---@return number g Green channel.
---@return number b Blue channel.
local function getBackgroundChannel(alignment, level, goodR, goodG, goodB, badR, badG, badB)
    local targetR, targetG, targetB = 0.5, 0.5, 0.5
    if alignment == 1 then
        targetR, targetG, targetB = goodR, goodG, goodB
    elseif alignment == 2 then
        targetR, targetG, targetB = badR, badG, badB
    end

    local ratio = level / 4
    return 0.5 + (targetR - 0.5) * ratio,
        0.5 + (targetG - 0.5) * ratio,
        0.5 + (targetB - 0.5) * ratio
end

--- Draws the tooltip of a custom moodle.
---@param element MoodlesUI Native drawing host.
---@param entry PallidMoodleEntry Entry under the mouse.
---@param localY number Local top coordinate of the slot.
local function drawTooltip(element, entry, localY)
    local title = entry.title or entry.id
    local description = entry.description or ""

    local textManager = getTextManager()
    local titleWidth = textManager:MeasureStringX(UIFont.Small, title)
    local descriptionWidth = textManager:MeasureStringX(UIFont.Small, description)
    local width = math.max(titleWidth, descriptionWidth)
    local titleHeight = textManager:MeasureStringY(UIFont.Small, title)
    local descriptionHeight = textManager:MeasureStringY(UIFont.Small, description)
    local height = titleHeight + descriptionHeight + 6

    element:DrawTextureScaledColor(nil, -10 - width - 6, localY - 2, width + 12, height, 0, 0, 0, 0.6)
    element:DrawTextRight(title, -10, localY, 1, 1, 1, 1)
    element:DrawTextRight(description, -10, localY + titleHeight + 2, 0.8, 0.8, 0.8, 1)
end

--- Draws the built-in moodle list.
---@param element MoodlesUI Native drawing host.
---@param entries PallidMoodleEntry[] Visible entries.
---@param count number Number of visible entries.
---@param layout PallidMoodleLayout Cached layout.
function Draw.drawDefault(element, entries, count, layout)
    local size = layout.size
    local spacing = layout.spacing
    local firstY = layout.firstY
    local background = getBackground(size)
    local border = getBorder(size)
    local goodColor = getCore():getGoodHighlitedColor()
    local badColor = getCore():getBadHighlitedColor()
    local goodR, goodG, goodB = goodColor:getR(), goodColor:getG(), goodColor:getB()
    local badR, badG, badB = badColor:getR(), badColor:getG(), badColor:getB()

    local absoluteX = element:getAbsoluteX()
    local absoluteY = element:getAbsoluteY()
    local mouseX = getMouseX()
    local mouseY = getMouseY()

    local slot = 0
    local hoverEntry = nil
    local hoverY = 0

    for i = 1, count do
        local entry = entries[i]
        if entry.definition.draw ~= false and entry.texture ~= nil then
            local localY = firstY + slot * spacing
            local r, g, b = getBackgroundChannel(
                entry.alignment, entry.level,
                goodR, goodG, goodB,
                badR, badG, badB
            )

            if background ~= nil then
                element:DrawTextureScaledColor(background, 0, localY, size, size, r, g, b, 1)
            end
            if border ~= nil then
                element:DrawTexture(border, 0, localY, 1)
            end
            element:DrawTextureScaledColor(entry.texture, 0, localY, size, size, 1, 1, 1, 1)

            if mouseX >= absoluteX and mouseX <= absoluteX + size
                and mouseY >= absoluteY + localY and mouseY <= absoluteY + localY + size then
                hoverEntry = entry
                hoverY = localY
            end

            slot = slot + 1
        end
    end

    if hoverEntry ~= nil then
        drawTooltip(element, hoverEntry, hoverY)
    end
end

return Draw
