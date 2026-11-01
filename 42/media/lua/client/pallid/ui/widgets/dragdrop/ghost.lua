require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/panel"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Color    = Pallid.UI.Color

local GHOST_PADDING   = 10
local GHOST_ICON_SIZE = 14
local GHOST_ICON_GAP  = 6
local GHOST_HEIGHT    = 28
local GHOST_OFFSET_X  = 12
local GHOST_OFFSET_Y  = 8
local GHOST_OPTS      = { mode = "fit" }

--- Floating preview painted by the root's overlay pass. It is never attached to
--- the widget tree, so it cannot affect hit testing or clipping.
--- @class PallidDragGhost : PallidPanel
local DragGhost = setmetatable({}, { __index = Widgets.Panel })
DragGhost.__index = DragGhost

--- Builds the single ghost widget for a session. Measurements happen once,
--- so moving the ghost is only two field writes.
--- @param payload PallidDragPayload Drag payload.
--- @return PallidDragGhost New drag ghost.
local function createGhost(payload)
    local label = payload.label
    if label == nil then
        label = ""
    else
        label = tostring(label)
    end

    local iconTexture, iconName
    local icon = payload.icon
    if type(icon) == "string" then
        iconTexture, iconName = Pallid.UI.Textures.resolve(icon)
    elseif icon ~= nil and icon.getWidth ~= nil then
        iconTexture = icon
    end

    local iconSize = payload.iconSize or GHOST_ICON_SIZE
    local hasIcon  = iconTexture ~= nil or iconName ~= nil
    local font     = Pallid.UI.Fonts.small
    local textW    = 0
    if label ~= "" then
        textW = getTextManager():MeasureStringX(font, label)
    end

    local width = payload.width
    if width == nil then
        width = GHOST_PADDING * 2 + textW
        if hasIcon then
            width = width + iconSize + GHOST_ICON_GAP
        end
        -- A very long label must not push the preview outside the window.
        if width > 360 then
            width = 360
        end
    end
    local height = payload.height or GHOST_HEIGHT

    local accent = payload.color
    local fill = Color.withAlpha(Color.panel, 0.9)
    local border
    if payload.border ~= nil then
        border = payload.border
    elseif accent ~= nil then
        border = Color.withAlpha(accent, 0.85)
    else
        border = Color.withAlpha(Color.panelBorder, 0.8)
    end

    local self = setmetatable(Widgets.Panel.new(0, 0, width, height, {
        background = fill,
        border     = border,
        radius     = 4,
    }), DragGhost)

    self.label       = label
    self.iconTexture = iconTexture
    self.iconName    = iconName
    self.iconSize    = iconSize
    self.iconColor   = accent or Color.textPrimary
    self.textX       = GHOST_PADDING + (hasIcon and (iconSize + GHOST_ICON_GAP) or 0)
    self.offsetX     = payload.offsetX or GHOST_OFFSET_X
    self.offsetY     = payload.offsetY or GHOST_OFFSET_Y
    self.style       = {
        font    = font,
        color   = Color.textPrimary,
        alignH  = "left",
        alignV  = "middle",
    }

    self.hittable = false
    self.cullable = false
    return self
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function DragGhost:drawSelf(el)
    Widgets.Panel.drawSelf(self, el)

    local x, y = self:originX(), self:originY()
    local cy = y + self.h * 0.5

    if self.iconTexture ~= nil then
        local ix = x + GHOST_PADDING
        local iy = y + (self.h - self.iconSize) * 0.5
        Pallid.UI.texture(el, self.iconTexture, ix, iy, self.iconSize, self.iconSize, self.iconColor, GHOST_OPTS)
    elseif self.iconName ~= nil then
        local ix = x + GHOST_PADDING
        local iy = y + (self.h - self.iconSize) * 0.5
        Pallid.UI.icon(el, self.iconName, ix, iy, self.iconSize, self.iconColor)
    end

    if self.label ~= "" then
        self.style.maxWidth = self.w - self.textX - GHOST_PADDING
        Pallid.UI.text(el, self.label, x + self.textX, cy, self.style)
    end
end

return createGhost
