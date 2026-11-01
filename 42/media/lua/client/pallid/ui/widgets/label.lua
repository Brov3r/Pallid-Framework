require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Single- or multi-line text block. Wrapping and ellipsis use the widget
--- width, so the layout only has to set the bounds.
--- @class PallidLabel : PallidWidget
--- @field text string Current label text.
--- @field style PallidTextStyle Resolved text style; `maxWidth` follows the widget width.
local Label = Widgets.class("Label")

--- Creates a new `Label` instance.
--- @param text string Initial label text.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels; wrapping and ellipsis use it.
--- @param h number Height in pixels; only used to anchor the text block.
--- @param opts table|nil Optional text and appearance settings.
--- @field opts.style PallidTextStyle|nil Full text style copied into the label.
--- @field opts.font UIFont|string|nil Font; defaults to Pallid.UI.Fonts.small.
--- @field opts.alignH "left"|"center"|"right"|nil Horizontal anchor; defaults to "left".
--- @field opts.alignV "top"|"middle"|"bottom"|nil Vertical anchor; defaults to "middle".
--- @field opts.wrap boolean|nil Enables word wrapping at the label width.
--- @field opts.ellipsis boolean|string|nil Ellipsis suffix; false disables it.
--- @field opts.maxLines integer|nil Maximum wrapped line count.
--- @field opts.color PallidColor|nil Text colour; overrides the style colour.
--- @return PallidLabel label The created label.
function Label.new(text, x, y, w, h, opts)
    opts = opts or {}
    local base = opts.style or {}
    local self = setmetatable({}, Label)
    self:init(x, y, w, h)

    -- Copy the whole style first so decoration fields (bold, underline, shadow,
    -- outline, ...) survive. Label-level options then override it.
    local style = {}
    for key, value in pairs(base) do
        style[key] = value
    end

    local color = opts.color or base.color or Pallid.UI.Color.text
    style.color = { r = color.r, g = color.g, b = color.b, a = color.a }
    style.font = opts.font or base.font or Pallid.UI.Fonts.small
    style.scale = base.scale or 1
    style.alignH = opts.alignH or base.alignH or "left"
    style.alignV = opts.alignV or base.alignV or "middle"

    if opts.wrap ~= nil then
        style.wrap = opts.wrap
    end
    if opts.maxLines ~= nil then
        style.maxLines = opts.maxLines
    end
    if opts.ellipsis ~= nil then
        style.ellipsis = opts.ellipsis
    end

    self.style = style
    self.text = text or ""
    -- Per-label layout cache: static labels must not re-measure or re-wrap on
    -- every frame.
    self._textCache = {}
    return self
end

--- Factory shortcut for `Label.new`.
--- @param text string Initial label text.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels; wrapping and ellipsis use it.
--- @param h number Height in pixels; only used to anchor the text block.
--- @param opts table|nil Optional text and appearance settings; see `Label.new`.
--- @return PallidLabel label The created label.
function Widgets.label(text, x, y, w, h, opts)
    return Label.new(text, x, y, w, h, opts)
end

--- Replaces the label text.
--- @param text string New text; nil becomes an empty string.
--- @return PallidLabel self For chaining.
function Label:setText(text)
    self.text = text or ""
    return self
end

--- Returns the current label text.
--- @return string text Current text; empty when nothing was set.
function Label:getText()
    return self.text
end

--- Replaces the text colour in place.
--- @param color PallidColor New colour; its components are copied.
--- @return PallidLabel self For chaining.
function Label:setColor(color)
    local styleColor = self.style.color
    styleColor.r = color.r
    styleColor.g = color.g
    styleColor.b = color.b
    styleColor.a = color.a
    return self
end

--- Returns the natural text size. Wrapping uses `maxW` when it is supplied.
--- @param maxW number|nil Available width in pixels.
--- @param maxH number|nil Available height in pixels; unused.
--- @return number width Preferred width in pixels.
--- @return number height Preferred height in pixels.
function Label:preferredSize(maxW, maxH)
    local style = self.style
    local previous = style.maxWidth
    style.maxWidth = maxW
    local width, height = Pallid.UI.measureText(self.text, style)
    style.maxWidth = previous
    if maxW ~= nil and width > maxW then
        width = maxW
    end
    return width, height
end

--- Draws the label into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Label:drawSelf(el)
    -- A zero-width label has no text box; drawing it would spill outside.
    if self.w <= 0 then
        return
    end
    local style = self.style
    style.maxWidth = self.w

    local x = self:originX()
    if style.alignH == "center" then
        x = x + self.w * 0.5
    elseif style.alignH == "right" then
        x = x + self.w
    end

    local y = self:originY()
    if style.alignV == "middle" then
        y = y + self.h * 0.5
    elseif style.alignV == "bottom" then
        y = y + self.h
    end

    local base = self.style.color
    self.style.color = self:shade(base)
    Pallid.UI.textPrepared(
        el,
        Pallid.UI.prepareText(self.text, style, self._textCache),
        x, y, style
    )
    self.style.color = base
end
