require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local mixInto = Pallid.UI.Color.mixInto

local FIELD_RADIUS = 4
local FIELD_PAD = 7
local FIELD_GAP = 6
local ICON_OPTS = { mode = "fit" }

-- Scratch color for the field fill: blended in place so hover and press do not
-- allocate a table per frame.
local FILL = { r = 1, g = 1, b = 1, a = 1 }

--- Shared compact field chrome for the time and date pickers: hover/press
--- animation, an icon, the caption and the popover lifecycle. Subclasses
--- provide `open()` and their own popover content.
--- @class PallidPickerField : PallidWidget
--- @field radius number Field corner radius.
--- @field fillInset number Inset of the rounded fill; keeps AA corners clean.
--- @field hover number Eased hover amount, 0..1.
--- @field press number Eased press amount, 0..1.
--- @field _text string Field caption.
--- @field iconName string|nil Registered icon name, when set.
--- @field iconTexture Texture|nil Texture path icon, when set.
--- @field popover PallidPopover|nil Lazily created popover.
local PickerField = Widgets.class("PickerField")

--- Initialises the shared field state.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Shared field options.
--- @field opts.radius number|nil Corner radius; defaults to 4.
--- @field opts.icon string|false|nil Registered icon name or texture path; false hides the icon.
--- @field opts.onChange function|nil Change callback owned by the subclass.
function PickerField:_initField(x, y, w, h, opts)
    self:init(x, y, w, h)

    self.radius = opts.radius or FIELD_RADIUS
    self.fillInset = 1
    self.hover = 0
    self.press = 0
    self._pressed = false
    self._text = ""
    self.iconName = nil
    self.iconTexture = nil

    self.fill = Pallid.UI.Color.surface
    self.hoverFill = Pallid.UI.Color.accentSoft
    self.pressFill = Pallid.UI.Color.surfaceMuted
    self.borderColor = Pallid.UI.Color.border
    self.iconColor = Pallid.UI.Color.textMuted
    self.style = {
        font     = Pallid.UI.Fonts.small,
        color    = Pallid.UI.Color.textPrimary,
        alignH   = "left",
        alignV   = "middle",
        ellipsis = "...",
    }

    if opts.icon ~= nil then
        self:setIcon(opts.icon)
    end
    return self
end

--- Accepts a registered icon name, a texture path containing a slash, or
--- false to hide the icon.
--- @param icon string|false|nil Icon name, texture path or false.
--- @return PallidPickerField self This field, for chaining.
function PickerField:setIcon(icon)
    self.iconTexture, self.iconName = Pallid.UI.Textures.resolve(icon)
    return self
end

--- Eases hover and press feedback.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function PickerField:onAnimate(now, dt)
    self.hover = Widgets.approach(self.hover, self._hover and 1 or 0, 14, dt)
    self.press = Widgets.approach(self.press, self._pressed and 1 or 0, 24, dt)
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the field accepted the press.
function PickerField:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    self._pressed = true
    return true
end

--- Handles a pointer release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function PickerField:onUp(px, py)
    local pressed = self._pressed
    self._pressed = false
    if pressed and self.enabled and self:isInside(px, py) then
        self:open()
    end
end

--- Closes the popup.
--- @return PallidPickerField self This field, for chaining.
function PickerField:close()
    if self.popover ~= nil then
        self.popover:close()
    end
    return self
end

--- Returns true while the popup is open.
--- @return boolean open True while the popover is visible.
function PickerField:isOpen()
    return self.popover ~= nil and self.popover.visible
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the field is rendered into.
function PickerField:drawSelf(el)
    local x, y = self:originX(), self:originY()

    mixInto(FILL, self.fill, self.hoverFill, self.hover)
    mixInto(FILL, FILL, self.pressFill, self.press * 0.7)

    local inset = self.fillInset
    local radius = self.radius
    if inset > 0 and type(radius) == "number" then
        -- Shrink the fill radius by the inset so its AA edge stays inside the
        -- border instead of leaking bright pixels at the corners.
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
            self:shade(FILL)
        )
    else
        Pallid.UI.rect(el, x + inset, y + inset,
            self.w - inset * 2, self.h - inset * 2, self:shade(FILL))
    end
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1,
        self:shade(self.borderColor, 2))

    local iconSize = self.h - 10
    local textX = x + FIELD_PAD
    if iconSize > 0 and (self.iconTexture ~= nil or self.iconName ~= nil) then
        local iconX = x + FIELD_PAD
        local iconY = y + (self.h - iconSize) * 0.5
        local tint = self:shade(self.iconColor)
        if self.iconTexture ~= nil then
            Pallid.UI.texture(el, self.iconTexture, iconX, iconY, iconSize, iconSize, tint, ICON_OPTS)
        else
            Pallid.UI.icon(el, self.iconName, iconX, iconY, iconSize, tint)
        end
        textX = iconX + iconSize + FIELD_GAP
    end

    self.style.maxWidth = math.max(0, x + self.w - FIELD_PAD - textX)
    local base = self.style.color
    self.style.color = self:shade(base)
    Pallid.UI.text(el, self._text, textX, y + self.h * 0.5, self.style)
    self.style.color = base
end

return PickerField
