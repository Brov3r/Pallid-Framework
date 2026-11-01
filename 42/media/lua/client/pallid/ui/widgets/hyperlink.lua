require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/url"
require "pallid/ui/animation/util"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/toast"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal

local ICON_DIR = "media/assets/ui/pallid/icons/"
local TEXT_OFFSET = 1
local WIDTH_PADDING = 2
local DEFAULT_HEIGHT = 18
local HOVER_SPEED = 14

--- Link-styled text: accent colour, an eased hover tint, an animated underline
--- and a click callback.
--- @class PallidHyperlink : PallidWidget
--- @field text string Link label.
--- @field url string|nil URL passed to `onClick` and opened when no callback is set.
--- @field onClick fun(link: PallidHyperlink, url: string|nil)|nil Click handler.
--- @field font UIFont Resolved font used for measuring and drawing.
--- @field style PallidTextStyle Reused text style; `maxWidth` follows the widget width.
--- @field color PallidColor Resting text colour.
--- @field hoverColor PallidColor Target colour of the animated hover.
--- @field hover number Eased hover amount, 0..1.
--- @field pressed boolean True between a press and its release.
--- @field fixedWidth boolean True when the width was supplied instead of measured.
--- @field lastResult boolean|nil Result of the last Pallid.UI.openUrl call.
--- @field lastHow string|nil How the last URL was opened or copied.
local Hyperlink = Widgets.class("Hyperlink")

--- Creates a new `Hyperlink` instance.
--- @param text string Link label.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number|nil Zero/nil means "measure the text".
--- @param h number|nil Defaults to 18; zero or negative also falls back to it.
--- @param opts table|nil Hyperlink options.
--- @field opts.url string|nil Passed to `onClick`.
--- @field opts.onClick fun(link: PallidHyperlink, url: string|nil)|nil Called when the link is activated.
--- @field opts.color PallidColor|nil Resting text colour.
--- @field opts.hoverColor PallidColor|nil Hover text and underline colour.
--- @field opts.font UIFont|string|nil Font or a key from Pallid.UI.Fonts.
--- @return PallidHyperlink New hyperlink widget.
function Hyperlink.new(text, x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Hyperlink)

    local font = opts.font or Pallid.UI.Fonts.small
    if type(font) == "string" then
        -- MeasureStringX expects a UIFont, so a font key must be resolved here.
        font = Pallid.UI.Fonts[font] or Pallid.UI.Fonts.small
    end
    self.font = font
    self.text = text or ""
    self.url = opts.url
    self.onClick = opts.onClick
    self.pressed = false
    self.hover = 0
    self.lastResult = nil
    self.lastHow = nil

    self.fixedWidth = w ~= nil and w > 0
    if not self.fixedWidth then
        w = getTextManager():MeasureStringX(self.font, self.text) + WIDTH_PADDING
    end
    local height = h
    if height == nil or height <= 0 then
        height = DEFAULT_HEIGHT
    end
    self:init(x, y, w, height)

    self.color = opts.color or Pallid.UI.Color.primary
    self.hoverColor = opts.hoverColor or Pallid.UI.Color.primaryStrong
    self.style = {
        font = self.font,
        color = self.color,
        alignH = "left",
        alignV = "middle",
    }
    -- Scratch colours for the eased tint and the underline; never allocated in draw.
    self._tint = { r = self.color.r, g = self.color.g, b = self.color.b, a = self.color.a or 1 }
    self._rule = { r = self.hoverColor.r, g = self.hoverColor.g, b = self.hoverColor.b, a = self.hoverColor.a or 1 }
    self:_measure()
    return self
end

--- Factory shortcut for `Hyperlink.new`.
--- @param text string Text to process.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number|nil Width in pixels.
--- @param h number|nil Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidHyperlink New hyperlink widget.
function Widgets.hyperlink(text, x, y, w, h, opts)
    return Hyperlink.new(text, x, y, w, h, opts)
end

--- Caches the size of the drawn label so draw does not measure it again.
function Hyperlink:_measure()
    self.style.maxWidth = math.max(1, self.w - WIDTH_PADDING)
    self._textW, self._textH = Pallid.UI.measureText(self.text, self.style)
end

--- Sets the text.
--- @param text string Link text.
--- @return PallidHyperlink self The same instance, for chaining.
function Hyperlink:setText(text)
    self.text = text or ""
    if not self.fixedWidth then
        self.w = getTextManager():MeasureStringX(self.font, self.text) + WIDTH_PADDING
    end
    self:_measure()
    return self
end

--- Returns the current text.
--- @return string text Current label; empty when nothing was set.
function Hyperlink:getText()
    return self.text
end

--- Moves and resizes the link. A zero/nil width returns to auto-measure; a
--- zero/nil height falls back to the default height.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number|nil Width in pixels; zero/nil measures the text.
--- @param h number|nil Height in pixels; zero/nil uses 18.
--- @return PallidHyperlink self For chaining.
function Hyperlink:setBounds(x, y, w, h)
    if w == nil or w <= 0 then
        self.fixedWidth = false
        w = getTextManager():MeasureStringX(self.font, self.text) + WIDTH_PADDING
    else
        self.fixedWidth = true
    end
    local height = h
    if height == nil or height <= 0 then
        height = DEFAULT_HEIGHT
    end
    Widgets.Widget.setBounds(self, x, y, w, height)
    self:_measure()
    return self
end

--- Eases the hover tint and the underline reveal. Per-frame so the transition
--- is frame-rate independent and does not step at the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Hyperlink:onAnimate(now, dt)
    self.hover = Widgets.approach(self.hover, (self._hover and self.enabled) and 1 or 0, HOVER_SPEED, dt)
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function Hyperlink:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    self.pressed = true
    return true
end

--- Handles a pointer release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Hyperlink:onUp(px, py)
    local pressed = self.pressed
    self.pressed = false
    if not (pressed and self.enabled and self:isInside(px, py)) then
        return
    end
    if self.onClick ~= nil then
        self.onClick(self, self.url)
    elseif self.url ~= nil then
        -- The engine only permits Indie Stone domains; Pallid.UI.openUrl copies
        -- other links to the clipboard and reports it.
        self.lastResult, self.lastHow = Pallid.UI.openUrl(self.url)
        if self.lastHow == "clipboard" then
            local root = self:getRoot()
            if root ~= nil and Widgets.toast ~= nil then
                local text = I.translate("UI_Pallid_LinkCopied", "Link copied to clipboard")
                Widgets.toast(text, {
                    corner   = "bottom-right",
                    duration = 2.5,
                    accent   = Pallid.UI.Color.warning,
                    icon     = ICON_DIR .. "copy.png",
                }):show(root)
            end
        end
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function Hyperlink:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local style = self.style
    style.maxWidth = math.max(1, self.w - WIDTH_PADDING)

    local base = style.color
    -- lerpColor writes into the scratch table; it does not return it.
    Pallid.UI.Anim.lerpColor(self._tint, self.color, self.hoverColor, self.hover)
    style.color = self:shade(self._tint)
    Pallid.UI.text(el, self.text, x + TEXT_OFFSET, y + self.h * 0.5, style)
    style.color = base

    if self.enabled and self.hover > 0.01 and self._textW > 0 and self._textH > 0 then
        local rule = self._rule
        rule.r = self.hoverColor.r
        rule.g = self.hoverColor.g
        rule.b = self.hoverColor.b
        rule.a = (self.hoverColor.a or 1) * self.hover
        local ruleY = y + self.h * 0.5 + self._textH * 0.5 - 1
        Pallid.UI.rect(el, x + TEXT_OFFSET, ruleY, self._textW * self.hover, 1, rule)
    end
end
