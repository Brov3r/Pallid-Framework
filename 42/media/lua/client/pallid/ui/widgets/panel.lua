require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Plain container: background, optional border and rounded corners. Children
--- are positioned relative to the panel's top-left corner. A decorative panel
--- can set `hittable = false` so it does not swallow hover from the widgets
--- behind it.
--- @class PallidPanel : PallidWidget
--- @field fill PallidColor|nil Background color; nil draws no fill.
--- @field borderColor PallidColor|nil Border color; nil draws no border.
--- @field borderWidth number Border thickness in pixels; 0 disables the border.
--- @field radius number|table Corner radius: a number for all corners or
---                            {tl, tr, br, bl}, matching Pallid.UI.roundedRect.
--- @field fillInset number Inset applied to the fill inside the border; keeps AA corners clean.
local Panel = Widgets.class("Panel")

--- Creates a new `Panel` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional appearance.
--- @field opts.background PallidColor|nil Fill color; nil leaves the panel transparent.
--- @field opts.border PallidColor|nil Border color; nil draws no border.
--- @field opts.borderWidth number|nil Border thickness; defaults to 1 when a border color is set.
--- @field opts.radius number|table|nil Corner radius; a number for all corners or {tl, tr, br, bl}.
--- @field opts.fillInset number|nil Inset applied to the fill; defaults to 0.
--- @return PallidPanel panel New panel instance.
function Panel.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Panel)
    self:init(x, y, w, h)

    local background = opts.background
    if background ~= nil then
        self.fill = { r = background.r, g = background.g, b = background.b, a = background.a }
    end

    local border = opts.border
    if border ~= nil then
        self.borderColor = { r = border.r, g = border.g, b = border.b, a = border.a }
        self.borderWidth = opts.borderWidth or 1
    else
        self.borderWidth = 0
    end

    self.radius = opts.radius or 0
    self.fillInset = opts.fillInset or 0
    return self
end

--- Factory shortcut for `Panel.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional appearance; see `Panel.new`.
--- @return PallidPanel panel New panel instance.
function Widgets.panel(x, y, w, h, opts)
    return Panel.new(x, y, w, h, opts)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Panel:drawSelf(el)
    local x, y = self:originX(), self:originY()

    if self.fill ~= nil then
        local inset = self.fillInset or 0
        local radius = self.radius
        if inset > 0 and type(radius) == "number" then
            -- Shrink the fill radius by the inset so its AA edges stay inside
            -- the border instead of leaking bright pixels at the corners.
            radius = math.max(0, radius - inset)
        end
        if radius ~= nil and radius ~= 0 then
            Pallid.UI.roundedRect(
                el,
                x + inset,
                y + inset,
                self.w - inset * 2,
                self.h - inset * 2,
                radius,
                self:shade(self.fill)
            )
        else
            Pallid.UI.rect(el, x + inset, y + inset,
                self.w - inset * 2, self.h - inset * 2, self:shade(self.fill))
        end
    end

    if self.borderColor ~= nil and self.borderWidth > 0 then
        if self.radius ~= nil and self.radius ~= 0 then
            Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, self.borderWidth, self:shade(self.borderColor))
        else
            Pallid.UI.border(el, x, y, self.w, self.h, self.borderWidth, self:shade(self.borderColor))
        end
    end
end
