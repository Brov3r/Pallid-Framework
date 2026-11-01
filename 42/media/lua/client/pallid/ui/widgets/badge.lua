require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Small pill or dot used as a counter/status marker. It can sit in the corner
--- of another widget because it is an ordinary positioned child.
--- @class PallidBadge : PallidWidget
--- @field text string Text shown inside a pill badge.
--- @field dot boolean True draws a plain circle without text.
--- @field color PallidColor Pill/dot fill.
--- @field textColor PallidColor Text colour; contrast by default.
--- @field borderColor PallidColor|nil Optional pill outline.
--- @field font UIFont|string Measured font.
--- @field padding number Horizontal text inset.
--- @field size number Dot diameter.
--- @field autoWidth boolean True while the width follows the text.
--- @field autoHeight boolean True while the height is left to the widget.
local Badge = Widgets.class("Badge")

--- @param color PallidColor Source colour.
--- @return PallidColor copy Independent colour table.
local function copyColor(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a or 1 }
end

--- Creates a new `Badge` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param opts table|nil Badge content and appearance.
--- @field opts.text string|nil Counter/status text.
--- @field opts.dot boolean|nil Draw a circle without text.
--- @field opts.color PallidColor|nil Fill colour; defaults to primaryStrong.
--- @field opts.textColor PallidColor|nil Text colour; defaults to a contrast colour.
--- @field opts.border PallidColor|nil Optional pill outline; ignored by dots.
--- @field opts.width number|nil Fixed width; auto-sized when omitted.
--- @field opts.height number|nil Fixed height, defaults to 18 or `size` for a dot.
--- @field opts.size number|nil Dot diameter, defaults to 8.
--- @field opts.padding number|nil Horizontal text padding, defaults to 6.
--- @field opts.font UIFont|string|nil Text font, defaults to Fonts.small.
--- @return PallidBadge badge New badge instance.
function Badge.new(x, y, opts)
    opts = opts or {}
    local self = setmetatable({}, Badge)

    self.text = opts.text or ""
    self.dot = opts.dot or false
    self.font = opts.font or Pallid.UI.Fonts.small
    self.padding = opts.padding or 6
    self.size = opts.size or 8
    self.autoWidth = opts.width == nil
    self.autoHeight = opts.height == nil

    local height = opts.height or (self.dot and self.size or 18)
    local width = opts.width
    if width == nil then
        if self.dot then
            width = self.size
        else
            width = math.max(height, getTextManager():MeasureStringX(self.font, self.text) + self.padding * 2)
        end
    end

    self:init(x, y, width, height)
    local color = opts.color or Pallid.UI.Color.primaryStrong
    self.color = Pallid.UI.Color.new(color.r, color.g, color.b, color.a or 1)
    self.textColor = opts.textColor and copyColor(opts.textColor) or Pallid.UI.Color.contrastText(self.color)
    self.borderColor = opts.border and copyColor(opts.border) or nil

    self.style = {
        font   = self.font,
        color  = self.textColor,
        alignH = "center",
        alignV = "middle",
    }
    return self
end

--- Factory shortcut for `Badge.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param opts table|nil Badge content and appearance; see `Badge.new`.
--- @return PallidBadge badge New badge instance.
function Widgets.badge(x, y, opts)
    return Badge.new(x, y, opts)
end

--- Replaces the badge text and auto-width.
--- @param text string New text; nil becomes an empty string.
--- @return PallidBadge self For chaining.
function Badge:setText(text)
    self.text = text or ""
    if self.autoWidth and not self.dot then
        self.w = math.max(self.h, getTextManager():MeasureStringX(self.font, self.text) + self.padding * 2)
    end
    return self
end

--- Replaces the fill and recomputes contrast text.
--- @param color PallidColor New fill colour.
--- @return PallidBadge self For chaining.
function Badge:setColor(color)
    self.color = copyColor(color)
    self.textColor = Pallid.UI.Color.contrastText(self.color)
    self.style.color = self.textColor
    return self
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Badge:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local radius = math.min(self.w, self.h) * 0.5

    if self.dot then
        Pallid.UI.circle(el, x + self.w * 0.5, y + self.h * 0.5, radius, self:shade(self.color))
    else
        Pallid.UI.roundedRect(el, x, y, self.w, self.h, radius, self:shade(self.color))
        if self.borderColor ~= nil then
            Pallid.UI.roundedBorder(el, x, y, self.w, self.h, radius, 1, self:shade(self.borderColor))
        end
    end

    if not self.dot and self.text ~= "" then
        local base = self.style.color
        local baseMaxWidth = self.style.maxWidth
        self.style.color = self:shade(base)
        self.style.maxWidth = math.max(0, self.w - self.padding * 2)
        Pallid.UI.text(el, self.text, x + self.w * 0.5, y + self.h * 0.5, self.style)
        self.style.maxWidth = baseMaxWidth
        self.style.color = base
    end
end
