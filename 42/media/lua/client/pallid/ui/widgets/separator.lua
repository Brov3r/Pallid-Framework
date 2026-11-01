require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Thin horizontal or vertical divider.
--- @class PallidSeparator : PallidWidget
--- @field vertical boolean True for a vertical line.
--- @field color PallidColor Line colour.
--- @field thickness number Line thickness in pixels; at least 1.
local Separator = Widgets.class("Separator")

--- Creates a new `Separator` instance.
--- @param vertical boolean True for a vertical line, false for horizontal.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param color PallidColor|nil Line colour; defaults to the theme border.
--- @param thickness number|nil Line thickness, defaults to 1.
--- @return PallidSeparator separator New separator instance.
function Separator.new(vertical, x, y, w, h, color, thickness)
    local self = setmetatable({}, Separator)
    self:init(x, y, w, h)
    self.vertical = vertical
    local base = color or Pallid.UI.Color.panelBorder
    self.color = { r = base.r, g = base.g, b = base.b, a = base.a }
    self.thickness = math.max(1, thickness or 1)
    -- Decorative lines must never steal hover from the widgets behind them.
    self.hittable = false
    return self
end

--- Factory shortcut for `Separator.new`.
--- @param vertical boolean True for a vertical line, false for horizontal.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param color PallidColor|nil Line colour; defaults to the theme border.
--- @param thickness number|nil Line thickness, defaults to 1.
--- @return PallidSeparator separator New separator instance.
function Widgets.separator(vertical, x, y, w, h, color, thickness)
    return Separator.new(vertical, x, y, w, h, color, thickness)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Separator:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local thickness = self.thickness
    if self.vertical then
        Pallid.UI.rect(el, x + (self.w - thickness) * 0.5, y, thickness, self.h, self:shade(self.color))
    else
        Pallid.UI.rect(el, x, y + (self.h - thickness) * 0.5, self.w, thickness, self:shade(self.color))
    end
end
