require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RADIUS = 4
local MIN_SIZE = 24

--- Keycap-style label: a small rounded rectangle with a key name. Optionally
--- clickable, so it can be reused in shortcuts and help screens.
--- @class PallidKeycap : PallidWidget
--- @field text string Key name shown on the cap.
--- @field pressed boolean True while the cap is held pressed.
--- @field onClick fun(keycap: PallidKeycap)|nil Click callback; nil makes the cap decorative.
--- @field autoWidth boolean True while the width follows the text.
--- @field font UIFont|string Measured font.
--- @field padding number Horizontal text inset.
--- @field radius number Corner radius.
local Keycap = Widgets.class("Keycap")

--- Creates a new `Keycap` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param opts table|nil Keycap content and appearance.
--- @field opts.text string|nil Key name.
--- @field opts.width number|nil Fixed width; auto-sized when omitted.
--- @field opts.height number|nil Cap height, defaults to 24.
--- @field opts.font UIFont|string|nil Font, defaults to the small code font.
--- @field opts.padding number|nil Horizontal text padding, defaults to 7.
--- @field opts.radius number|nil Corner radius, defaults to 4.
--- @field opts.onClick fun(keycap: PallidKeycap)|nil Click callback; nil makes the cap decorative.
--- @return PallidKeycap keycap New keycap instance.
function Keycap.new(x, y, opts)
    opts = opts or {}
    local self = setmetatable({}, Keycap)

    self.text = opts.text or ""
    self.font = opts.font or Pallid.UI.Fonts.codeSmall
    self.padding = opts.padding or 7
    self.onClick = opts.onClick
    self.pressed = false
    self.autoWidth = opts.width == nil
    self.radius = opts.radius or RADIUS

    local height = math.max(2, opts.height or MIN_SIZE)
    local width = opts.width or math.max(MIN_SIZE, getTextManager():MeasureStringX(self.font, self.text) + self.padding * 2)
    self:init(x, y, width, height)

    self.fill = Pallid.UI.Color.surfaceMuted
    self.hoverFill = Pallid.UI.Color.accentSoft
    self.pressFill = Pallid.UI.Color.primarySoft
    self.borderColor = Pallid.UI.Color.border
    self.textColor = Pallid.UI.Color.textPrimary
    self.style = {
        font = self.font,
        color = self.textColor,
        alignH = "center",
        alignV = "middle",
    }
    return self
end

--- Factory shortcut for `Keycap.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param opts table|nil Keycap settings; see `Keycap.new`.
--- @return PallidKeycap keycap New keycap instance.
function Widgets.keycap(x, y, opts)
    return Keycap.new(x, y, opts)
end

--- Replaces the key name and auto-width.
--- @param text string New key name; nil becomes an empty string.
--- @return PallidKeycap self For chaining.
function Keycap:setText(text)
    self.text = text or ""
    if self.autoWidth then
        self.w = math.max(MIN_SIZE, getTextManager():MeasureStringX(self.font, self.text) + self.padding * 2)
    end
    return self
end

--- Starts a press on a clickable keycap.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function Keycap:onDown(px, py, button)
    if button == "right" or not self.enabled or self.onClick == nil then
        return false
    end
    self.pressed = true
    return true
end

--- Completes a click when the release is inside the cap.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Keycap:onUp(px, py)
    local pressed = self.pressed
    self.pressed = false
    if pressed and self.enabled and self.onClick ~= nil and self:isInside(px, py) then
        self.onClick(self)
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Keycap:drawSelf(el)
    local x, y = self:originX(), self:originY()

    -- A darker lip under the cap reads as physical depth.
    Pallid.UI.roundedRect(el, x, y + 2, self.w, self.h, self.radius, self:shade(Pallid.UI.Color.background))

    local hover = self.enabled and self._hover
    local fill = self.pressed and self.pressFill or (hover and self.hoverFill or self.fill)
    Pallid.UI.roundedRect(el, x, y, self.w, self.h - 2, self.radius, self:shade(fill))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h - 2, self.radius, 1, self:shade(self.borderColor))

    local style = self.style
    local base = style.color
    local baseMaxWidth = style.maxWidth
    style.color = self:shade(base)
    style.maxWidth = math.max(0, self.w - self.padding * 2)
    Pallid.UI.text(el, self.text, x + self.w * 0.5, y + (self.h - 2) * 0.5, style)
    style.maxWidth = baseMaxWidth
    style.color = base
end
