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

local DEFAULT_RADIUS = 4
local DEFAULT_SOUND = "UIActivateButton"
local GAP = 6
local PADDING = 6
local DEFAULT_ICON_INSET = 10

--- Button with optional icon, toggle mode and click sound. Hover, press and
--- the active (toggle) fill are eased in `onAnimate`, so the transition is
--- frame-rate independent and costs three numbers per frame.
---
--- With `background = false` only the content is drawn; the icon tint still
--- reacts to hover and press, which makes the button usable as a caption icon.
--- @class PallidButton : PallidWidget
--- @field text string Label; an empty string leaves only the icon.
--- @field icon string|nil Registered icon name or a texture path containing a slash.
--- @field iconTexture Texture|nil Resolved texture for a path icon.
--- @field iconSide "left"|"right" Side of the icon relative to the label.
--- @field iconColor PallidColor|nil Icon tint; nil draws it white.
--- @field iconInset number Pixels trimmed from every side of the icon box.
--- @field background boolean True draws the fill and border.
--- @field flat boolean True uses a plain rect chrome instead of rounded corners.
--- @field border boolean False skips the chrome border when `background` is drawn.
--- @field toggle boolean When true a click flips `active`.
--- @field active boolean Current toggle state.
--- @field sound string|nil UI sound name; nil is silent.
--- @field onClick fun(button: PallidButton)|nil Called after the toggle state is updated.
--- @field hover number Eased hover amount, 0..1.
--- @field press number Eased press amount, 0..1.
--- @field activeT number Eased active amount, 0..1.
local Button = Widgets.class("Button")

--- Creates a new `Button` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional content and behaviour.
--- @field opts.text string|nil Button label.
--- @field opts.icon string|nil Registered icon name, or a texture path containing a slash.
--- @field opts.iconSide "left"|"right"|nil Icon side; defaults to "left".
--- @field opts.toggle boolean|nil When true a click flips the active state.
--- @field opts.active boolean|nil Initial toggle state.
--- @field opts.onClick fun(button: PallidButton)|nil Called on a completed click.
--- @field opts.sound string|false|nil Sound name; nil keeps the default, false or "" silences it.
--- @field opts.radius number|table|nil Corner radius; a number for all corners or {tl, tr, br, bl}.
--- @field opts.background boolean|nil Draws the fill and border; defaults to true.
--- @field opts.flat boolean|nil Uses a plain rect instead of rounded chrome; useful in dense lists.
--- @field opts.border boolean|nil False skips the chrome border; defaults to true.
--- @field opts.iconColor PallidColor|nil Icon tint; nil draws it white.
--- @field opts.iconInset number|nil Icon inset from every side; defaults to 10.
--- @return PallidButton button New button instance.
function Button.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Button)
    self:init(x, y, w, h)

    self.text = opts.text or ""
    self.iconSide = opts.iconSide == "right" and "right" or "left"
    self.toggle = opts.toggle or false
    self.active = opts.active or false
    self.onClick = opts.onClick
    self.radius = opts.radius or DEFAULT_RADIUS
    self.background = opts.background ~= false
    self.flat = opts.flat == true
    self.border = opts.border ~= false
    self.iconColor = opts.iconColor
    self.iconInset = opts.iconInset or DEFAULT_ICON_INSET
    self.iconOpts = { mode = "fit" }

    -- nil keeps the default click sound; false and "" are the explicit "silent".
    local sound = opts.sound
    if sound == nil then
        sound = DEFAULT_SOUND
    elseif sound == false or sound == "" then
        sound = nil
    end
    self.sound = sound

    self.hover = 0
    self.press = 0
    self.activeT = self.active and 1 or 0
    self.pressed = false
    self._textCache = {}

    self.fill = Pallid.UI.Color.surface
    self.hoverFill = Pallid.UI.Color.accentSoft
    self.pressFill = Pallid.UI.Color.surfaceMuted
    self.activeFill = Pallid.UI.Color.primarySoft
    self.borderColor = Pallid.UI.Color.border
    self.textColor = Pallid.UI.Color.textPrimary
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "left",
        alignV = "middle",
    }

    if opts.icon ~= nil then
        self:setIcon(opts.icon)
    end

    return self
end

--- Factory shortcut for `Button.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional content and behaviour; see `Button.new`.
--- @return PallidButton button New button instance.
function Widgets.button(x, y, w, h, opts)
    return Button.new(x, y, w, h, opts)
end

--- Replaces the label.
--- @param text string New label; an empty string hides it.
--- @return PallidButton self For chaining.
function Button:setText(text)
    self.text = text or ""
    return self
end

--- Replaces the icon. A nil or empty value removes it. A string containing a
--- slash is loaded as a texture path; any other string is an icon name
--- registered with Pallid.UI.Textures.registerIcon.
--- @param icon string|nil Icon name, texture path, or nil to clear.
--- @return PallidButton self For chaining.
function Button:setIcon(icon)
    if icon == nil or icon == "" then
        self.icon = nil
        self.iconTexture = nil
        self.iconRegion = nil
        self._iconWarned = nil
        return self
    end
    self.icon = icon
    self._iconWarned = nil
    self.iconRegion = nil
    if string.find(icon, "/", 1, true) ~= nil then
        self.iconRegion = Pallid.UI.Textures.getRegion(icon)
        self.iconTexture = self.iconRegion == nil and Pallid.UI.Textures.get(icon) or nil
    else
        -- Resolve registered names once so drawIcon can use the atlas region
        -- instead of a registry lookup on every frame.
        self.iconRegion = Pallid.UI.Textures.getIconRegion(icon)
        self.iconTexture = self.iconRegion == nil and Pallid.UI.Textures.getIcon(icon) or nil
    end
    return self
end

--- True when the icon can be drawn: a loaded path texture or a name registered
--- with Pallid.UI.Textures.registerIcon. Warns once per icon when neither.
--- @return boolean available True when the icon can be drawn.
function Button:hasIcon()
    if self.iconRegion ~= nil or self.iconTexture ~= nil then
        return true
    end
    if self.icon == nil then
        return false
    end
    if string.find(self.icon, "/", 1, true) ~= nil then
        -- A path that failed to load: Textures.get already logged it once.
        return false
    end
    if Pallid.UI.Textures.hasIcon(self.icon) then
        return true
    end
    if not self._iconWarned then
        self._iconWarned = true
        Pallid.log("Button: icon '" .. tostring(self.icon) ..
            "' is neither a texture path nor a registered icon")
    end
    return false
end

--- Changes the toggle state. The fill eases to it on the next frame, so a
--- programmatic change is animated too.
--- @param active boolean New state.
--- @return PallidButton self For chaining.
function Button:setActive(active)
    self.active = active
    return self
end

--- Returns the current toggle state.
--- @return boolean active Current toggle state.
function Button:getActive()
    return self.active
end

--- Eases hover, press and active fills. Per-frame so the fill does not step at
--- the game tick. A disabled button does not react to hover.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Button:onAnimate(now, dt)
    self.hover = Widgets.approach(self.hover, (self._hover and self.enabled) and 1 or 0, 14, dt)
    self.press = Widgets.approach(self.press, self.pressed and 1 or 0, 24, dt)
    self.activeT = Widgets.approach(self.activeT, self.active and 1 or 0, 14, dt)
end

--- Starts a press. Right-click is ignored so a context click cannot leave the
--- button stuck in the pressed state (or fire a click inside an overlay).
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function Button:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    self.pressed = true
    return true
end

--- Completes a click: toggles first (so `onClick` sees the new state), plays the
--- sound and calls the callback. A release outside the button cancels it.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Button:onUp(px, py)
    local pressed = self.pressed
    self.pressed = false
    if not pressed or not self.enabled or not self:isInside(px, py) then
        return
    end

    if self.toggle then
        self.active = not self.active
    end

    local sound = self.sound
    if sound ~= nil and getSoundManager ~= nil then
        local manager = getSoundManager()
        if manager ~= nil then
            manager:playUISound(sound)
        end
    end

    if self.onClick ~= nil then
        self.onClick(self)
    end
end

local BASE = { r = 0, g = 0, b = 0, a = 1 }
local ACTIVE = { r = 0, g = 0, b = 0, a = 1 }
local PRESSED = { r = 0, g = 0, b = 0, a = 1 }

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Button:drawSelf(el)
    local x, y = self:originX(), self:originY()

    if self.background then
        mixInto(BASE, self.fill, self.hoverFill, self.hover)
        mixInto(ACTIVE, BASE, self.activeFill, self.activeT)
        mixInto(PRESSED, ACTIVE, self.pressFill, self.press * 0.7)

        -- shade() reuses one scratch table per slot: the fill is consumed by the
        -- rectangle below before drawContent asks for the text and icon tints.
        local fill = self:shade(PRESSED)
        local border = self:shade(self.borderColor, 2)
        local inset = self.fillInset or 0
        local flat = self.flat or self.radius == 0
        if flat then
            -- Dense lists can trade rounded chrome for 1-5 sprite submissions.
            Pallid.UI.rect(el, x + inset, y + inset, self.w - inset * 2, self.h - inset * 2, fill)
            if self.border then
                Pallid.UI.border(el, x, y, self.w, self.h, 1, border)
            end
        else
            local fillRadius = self.radius
            if inset > 0 and type(fillRadius) == "number" then
                fillRadius = math.max(0, fillRadius - inset)
            end
            Pallid.UI.roundedRect(
                el,
                x + inset,
                y + inset,
                self.w - inset * 2,
                self.h - inset * 2,
                fillRadius,
                fill
            )
            if self.border then
                Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, border)
            end
        end
    end

    self:drawContent(el, x, y)
end

--- Returns the width needed for the label and icon at the current height.
--- @param maxW number|nil Available width in pixels.
--- @param maxH number|nil Available height in pixels.
--- @return number width Preferred width in pixels.
--- @return number height Preferred height in pixels.
function Button:preferredSize(maxW, maxH)
    local height = self.h
    local iconSize = math.max(0, math.min(height - self.iconInset, (maxW or self.w) - self.iconInset))
    local iconW = iconSize > 0 and self:hasIcon() and iconSize or 0
    local textW = self.text ~= "" and getTextManager():MeasureStringX(self.style.font, self.text) or 0
    local gap = (iconW > 0 and textW > 0) and GAP or 0
    local width = PADDING * 2 + iconW + gap + textW
    if maxW ~= nil and width > maxW then
        width = maxW
    end
    return width, height
end

--- Draws the centred icon/text pair. The label is truncated with an ellipsis
--- when it does not fit, so it never spills outside the button.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param x number Absolute X of the button.
--- @param y number Absolute Y of the button.
function Button:drawContent(el, x, y)
    local text = self.text
    local style = self.style
    local iconSize = math.max(0, math.min(self.h - self.iconInset, self.w - self.iconInset))
    local hasIcon = iconSize > 0 and self:hasIcon()

    local innerWidth = math.max(0, self.w - PADDING * 2)
    local showText = false
    local textWidth = 0
    local prepared
    if text ~= "" and innerWidth > 0 then
        local reserve = hasIcon and (iconSize + GAP) or 0
        local maxTextWidth = innerWidth - reserve
        if maxTextWidth > 0 then
            style.maxWidth = maxTextWidth
            prepared = Pallid.UI.prepareText(text, style, self._textCache)
            textWidth = Pallid.UI.measurePrepared(prepared)
            showText = textWidth > 0
        end
    end
    if not showText then
        style.maxWidth = nil
        prepared = nil
    end

    if not showText and not hasIcon then
        return
    end

    local gap = (showText and hasIcon) and GAP or 0
    local contentWidth = textWidth + (hasIcon and iconSize or 0) + gap
    local cursor = x + (self.w - contentWidth) * 0.5
    local iconY = y + (self.h - iconSize) * 0.5
    local textX = cursor
    local textY = y + self.h * 0.5

    if hasIcon and self.iconSide == "left" then
        self:drawIcon(el, cursor, iconY, iconSize)
        cursor = cursor + iconSize + gap
        textX = cursor
    elseif hasIcon then
        textX = cursor
        self:drawIcon(el, cursor + textWidth + gap, iconY, iconSize)
    end

    if showText and prepared ~= nil then
        local base = style.color
        style.color = self:shade(base)
        Pallid.UI.textPrepared(el, prepared, textX, textY, style)
        style.color = base
    end
end

local ICON_TINT = { r = 1, g = 1, b = 1, a = 1 }

--- @param value number Value to clamp into the 0..1 range.
--- @return number clamped Clamped value.
local function clamp01(value)
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

--- Draws the icon. A tint from `iconColor` brightens on hover and darkens on
--- press, which is the only feedback when `background` is false. Disabled
--- buttons dim the tint.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param x number Absolute X of the icon box.
--- @param y number Absolute Y of the icon box.
--- @param size number Square size in pixels.
function Button:drawIcon(el, x, y, size)
    local base = self.iconColor
    local tint
    if base == nil then
        if not self.enabled then
            tint = self:shade(Pallid.UI.Color.white, 3)
        end
    elseif not self.enabled then
        tint = self:shade(base, 3)
    else
        local t = self.hover * 0.25 - self.press * 0.15
        ICON_TINT.r = clamp01(base.r + (1 - base.r) * t)
        ICON_TINT.g = clamp01(base.g + (1 - base.g) * t)
        ICON_TINT.b = clamp01(base.b + (1 - base.b) * t)
        ICON_TINT.a = base.a or 1
        tint = ICON_TINT
    end
    if self.iconRegion ~= nil then
        Pallid.UI.textureRegion(el, self.iconRegion, x, y, size, size, tint, self.iconOpts)
    elseif self.iconTexture ~= nil then
        Pallid.UI.texture(el, self.iconTexture, x, y, size, size, tint, self.iconOpts)
    else
        Pallid.UI.icon(el, self.icon, x, y, size, tint)
    end
end
