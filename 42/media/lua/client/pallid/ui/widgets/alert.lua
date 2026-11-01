require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/animation/track"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local PADDING = 14
local ICON_SIZE = 20
local ICON_GAP = 12
local CLOSE_SIZE = 20
local MIN_HEIGHT = 44
local DEFAULT_RADIUS = 8
local ICON_OPTS = { mode = "fit" }

local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICONS = {
    info    = "pallid_alert_info",
    success = "pallid_alert_success",
    warning = "pallid_alert_warning",
    danger  = "pallid_alert_danger",
    neutral = "pallid_alert_neutral",
    close   = "pallid_alert_close",
}
Pallid.UI.Textures.registerIcon(ICONS.info, ICON_DIR .. "info-02.png")
Pallid.UI.Textures.registerIcon(ICONS.success, ICON_DIR .. "tick.png")
Pallid.UI.Textures.registerIcon(ICONS.warning, ICON_DIR .. "exclamation.png")
Pallid.UI.Textures.registerIcon(ICONS.danger, ICON_DIR .. "prohibited.png")
Pallid.UI.Textures.registerIcon(ICONS.neutral, ICON_DIR .. "notification.png")
Pallid.UI.Textures.registerIcon(ICONS.close, ICON_DIR .. "cross.png")

--- Writes `color` with multiplied alpha into `out`. Per-instance scratch
--- colours are used because several of them are needed in one draw call.
--- @param out PallidColor Scratch colour written in place.
--- @param color PallidColor Source colour.
--- @param alpha number Alpha multiplier, 0..1.
--- @return PallidColor out The same scratch table, for chaining.
local function setTint(out, color, alpha)
    out.r = color.r or 1
    out.g = color.g or 1
    out.b = color.b or 1
    out.a = (color.a or 1) * alpha
    return out
end

local SEVERITY = {
    info = {
        color = Pallid.UI.Color.info,
        icon  = ICONS.info,
    },
    success = {
        color = Pallid.UI.Color.success,
        icon  = ICONS.success,
    },
    warning = {
        color = Pallid.UI.Color.warning,
        icon  = ICONS.warning,
    },
    danger = {
        color = Pallid.UI.Color.danger,
        icon  = ICONS.danger,
    },
    neutral = {
        color = Pallid.UI.Color.secondary,
        icon  = ICONS.neutral,
    },
}

-- Friendly aliases: the palette already calls these colours warning/error.
SEVERITY.warn = SEVERITY.warning
SEVERITY.error = SEVERITY.danger

--- Horizontal, non-blocking message with a tinted severity icon, text and an
--- optional close button.
---
--- The banner is meant for lists and page headers: it never takes input outside
--- its close button, so clicks pass through to whatever is underneath. It also
--- paints in the overlay pass, above content added later in the same parent.
--- @class PallidAlert : PallidWidget
--- @field severity string "info"|"success"|"warning"|"danger"|"neutral"; "warn"/"error" are aliases.
--- @field title string Bold first line; empty hides it.
--- @field message string Wrapped body text; empty hides it.
--- @field closable boolean True draws the close button and enables dismissal.
--- @field accent PallidColor Severity or custom accent colour.
--- @field iconColor PallidColor Tint applied to the status icon.
--- @field onClose fun(alert: PallidAlert)|nil Called once the close animation ends.
--- @field entry PallidAnimTrack Entrance slide/fade track.
--- @field outro PallidAnimTrack Exit slide/fade track.
--- @field iconTexture Texture|nil Resolved texture when a path icon is used.
--- @field iconName string|nil Custom registered icon name, nil for the severity icon.
local Alert = Widgets.class("Alert")

--- Creates a new `Alert` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels; 0 measures it from the text.
--- @param opts table|nil Appearance and severity overrides.
--- @field opts.severity "info"|"success"|"warning"|"danger"|"neutral"|"warn"|"error"|nil Defaults to "info".
--- @field opts.title string|nil Optional bold first line.
--- @field opts.message string|nil Main text; wraps to three lines by default.
--- @field opts.closable boolean|nil Defaults to true.
--- @field opts.onClose fun(alert: PallidAlert)|nil Called once the banner is dismissed.
--- @field opts.color PallidColor|nil Overrides the severity accent.
--- @field opts.background PallidColor|nil Panel fill; defaults to the neutral elevated surface.
--- @field opts.border PallidColor|nil Panel border; defaults to the neutral border token.
--- @field opts.textColor PallidColor|nil Message colour.
--- @field opts.titleColor PallidColor|nil Title colour.
--- @field opts.icon string|false|nil Registered icon, texture path, or false to hide it.
--- @field opts.iconSize number|nil Status icon size, defaults to 20.
--- @field opts.iconGap number|nil Space between the icon and the text, defaults to 12.
--- @field opts.iconColor PallidColor|nil Icon tint; defaults to the severity accent.
--- @field opts.font UIFont|string|nil Title and message font.
--- @field opts.maxLines integer|nil Message line cap, defaults to 3.
--- @field opts.radius number|nil Corner radius, defaults to 8.
--- @field opts.animated boolean|nil Slide and fade in/out; defaults to true.
--- @field opts.padding number|nil Inner padding, defaults to 14.
--- @field opts.closeSize number|nil Close button box size, defaults to 20.
--- @return PallidAlert alert New banner instance.
function Alert.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Alert)
    self:init(x, y, w, h)

    self.severity = opts.severity or "info"
    self.title = opts.title or ""
    self.message = opts.message or ""
    self.closable = opts.closable ~= false
    self.onClose = opts.onClose
    self.padding = opts.padding or PADDING
    self.iconSize = opts.iconSize or ICON_SIZE
    self.iconGap = opts.iconGap or ICON_GAP
    self.closeSize = opts.closeSize or CLOSE_SIZE
    self.radius = opts.radius or DEFAULT_RADIUS
    self.showIcon = opts.icon ~= false
    self.animated = opts.animated ~= false
    self:setOverlay(true)
    self._closePressed = false
    self._closeHover = false
    self._closeHoverT = 0
    self._closed = false
    self._closing = false
    self._fillTint = { r = 1, g = 1, b = 1, a = 1 }
    self._borderTint = { r = 1, g = 1, b = 1, a = 1 }
    self._iconTint = { r = 1, g = 1, b = 1, a = 1 }
    self._closeTint = { r = 1, g = 1, b = 1, a = 1 }
    self._closeBg = { r = 0, g = 0, b = 0, a = 0 }

    self.titleStyle = {
        font = opts.font or Pallid.UI.Fonts.small,
        color = opts.titleColor or Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "top",
        bold = true,
        ellipsis = "...",
    }
    self.messageStyle = {
        font = opts.font or Pallid.UI.Fonts.small,
        color = opts.textColor or Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "top",
        wrap = true,
        maxLines = opts.maxLines or 3,
        ellipsis = "...",
        lineSpacing = 1,
    }

    self.entry = Pallid.UI.Anim.new({
        duration = 0.3,
        easing = Pallid.UI.Anim.ease.outCubic,
        alpha = { 0, 1 },
        dx = { -14, 0 },
    })
    self.outro = Pallid.UI.Anim.new({
        duration = 0.2,
        easing = Pallid.UI.Anim.ease.inCubic,
        alpha = { 1, 0 },
        dx = { 0, 14 },
    })

    self._customAccent = opts.color
    self._customBackground = opts.background
    self._customBorder = opts.border
    self._customIconColor = opts.iconColor
    self:setIcon(opts.icon)
    self:_applySeverity()

    self:_layout()
    if self.animated then
        self.entry:play()
    end
    return self
end

--- Factory shortcut for `Alert.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels; 0 measures it from the text.
--- @param opts table|nil Appearance and severity overrides; see `Alert.new`.
--- @return PallidAlert alert New banner instance.
function Widgets.alert(x, y, w, h, opts)
    return Alert.new(x, y, w, h, opts)
end

--- Recomputes the accent-derived palette. Called on construction and when the
--- severity changes, never per frame.
function Alert:_applySeverity()
    local spec = SEVERITY[self.severity] or SEVERITY.info
    self._severityIcon = spec.icon
    self.accent = self._customAccent or spec.color
    self.fill = self._customBackground or Pallid.UI.Color.surfaceElevated
    self.borderColor = self._customBorder or Pallid.UI.Color.border
    self.iconColor = self._customIconColor or self.accent
end

--- Measures wrapped text and places the icon, text block and close button.
function Alert:_layout()
    local iconBlock = self.showIcon and self.iconSize or 0
    local closeBlock = self.closable and (self.closeSize + 8) or 0
    local left = self.padding + (iconBlock > 0 and (iconBlock + self.iconGap) or 0)
    local right = self.padding + closeBlock + 4
    local textW = math.max(20, self.w - left - right)

    local titleH = 0
    if self.title ~= "" then
        self.titleStyle.maxWidth = textW
        titleH = select(2, Pallid.UI.measureText(self.title, self.titleStyle))
    end

    local messageH = 0
    if self.message ~= "" then
        self.messageStyle.maxWidth = textW
        messageH = select(2, Pallid.UI.measureText(self.message, self.messageStyle))
    end

    local contentH = titleH + messageH
    if titleH > 0 and messageH > 0 then
        contentH = contentH + 2
    end

    if self.h <= 0 then
        self.h = math.max(MIN_HEIGHT, contentH + self.padding * 2)
    end

    local top = (self.h - contentH) * 0.5
    self._titleY = top
    self._messageY = top + titleH + ((titleH > 0 and messageH > 0) and 2 or 0)
    self._textX = left
    self._iconX = self.padding
    self._iconY = (self.h - self.iconSize) * 0.5
    self._closeX = self.w - self.padding - self.closeSize
    self._closeY = (self.h - self.closeSize) * 0.5
end

--- Updates the widget bounds.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels; 0 measures it from the text.
--- @return PallidAlert self For chaining.
function Alert:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_layout()
    return self
end

--- Sets the title text.
--- @param title string Bold first line; empty hides it.
--- @return PallidAlert self For chaining.
function Alert:setTitle(title)
    self.title = title or ""
    self:_layout()
    return self
end

--- Sets the message text.
--- @param message string Wrapped body text; empty hides it.
--- @return PallidAlert self For chaining.
function Alert:setMessage(message)
    self.message = message or ""
    self:_layout()
    return self
end

--- Sets the alert severity.
--- @param severity string "info"|"success"|"warning"|"danger"|"neutral"; "warn"/"error" are aliases.
--- @return PallidAlert self For chaining.
function Alert:setSeverity(severity)
    self.severity = severity or "info"
    self:_applySeverity()
    return self
end

--- Sets whether the alert can be closed.
--- @param closable boolean True shows the close button and enables dismissal.
--- @return PallidAlert self For chaining.
function Alert:setClosable(closable)
    self.closable = closable
    self:_layout()
    return self
end

--- @param icon string|false|nil Registered icon, texture path, false to hide the
--- block, or nil to fall back to the severity icon.
--- @return PallidAlert self For chaining.
function Alert:setIcon(icon)
    self.iconTexture = nil
    self.iconName = nil
    if type(icon) == "string" then
        if string.find(icon, "/", 1, true) ~= nil then
            self.iconTexture = Pallid.UI.Textures.get(icon)
        else
            self.iconName = icon
        end
        self.showIcon = true
    elseif icon == false then
        self.showIcon = false
    else
        -- nil restores the severity icon, so a hidden icon can be brought back.
        self.showIcon = true
    end
    self:_layout()
    return self
end

--- Returns the horizontal offset produced by the entrance/exit animation. It is
--- shared by the draw code and the close-button hit test, so a press follows
--- the button while the banner is still sliding in.
--- @return number dx Offset in pixels; 0 when animation is disabled.
function Alert:_shiftX()
    if not self.animated then
        return 0
    end
    local dx = self.entry.dx or 0
    if self._closing then
        dx = dx + (self.outro.dx or 0)
    end
    return dx
end

--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the cursor is over the close button.
function Alert:_isInClose(px, py)
    if not self.closable then
        return false
    end
    local x = self:originX() + self:_shiftX() + self._closeX
    local y = self:originY() + self._closeY
    return px >= x and px < x + self.closeSize and py >= y and py < y + self.closeSize
end

--- Reopens a banner that was closed and replays the entrance. The close
--- callback is not called again until the banner is dismissed a second time.
--- @return PallidAlert self For chaining.
function Alert:show()
    self._closed = false
    self._closing = false
    self.visible = true
    self._closePressed = false
    self._closeHover = false
    self._closeHoverT = 0
    self.outro:stop()
    if self.animated then
        self.entry:play()
    end
    return self
end

--- Dismisses the banner. With animation enabled the exit slide/fade runs first
--- and `onClose` fires when it finishes; pass `true` to hide immediately, even
--- while an exit animation is already running.
--- @param immediate boolean|nil True skips the exit animation.
--- @return PallidAlert self For chaining.
function Alert:close(immediate)
    if self._closed then
        return self
    end
    self._closePressed = false
    if immediate or not self.animated then
        self:_finishClose()
    elseif not self._closing then
        self._closing = true
        self.outro:play()
    end
    return self
end

--- Hides the banner and fires `onClose` once.
function Alert:_finishClose()
    if self._closed then
        return
    end
    self._closed = true
    self._closing = false
    self.visible = false
    if self.onClose ~= nil then
        self.onClose(self)
    end
end

--- Eases the close-button hover and advances the entrance/exit tracks.
--- Per-frame so the alert fades and slides smoothly.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Alert:onAnimate(now, dt)
    self._closeHoverT = Widgets.approach(self._closeHoverT, self._closeHover and 1 or 0, 18, dt)
    if not self.animated then
        return
    end
    self.entry:update(now)
    if self._closing then
        self.outro:update(now)
    end
end

--- Closes the alert once the exit animation has finished. Kept on the game tick
--- because it hides the widget and fires onClose, which changes structure.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function Alert:onUpdate(now, dt)
    if self.animated and self._closing and self.outro.finished then
        self:_finishClose()
    end
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press captured the close button.
function Alert:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    if self:_isInClose(px, py) then
        self._closePressed = true
        return true
    end
    return false
end

--- Handles a pointer release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Alert:onUp(px, py)
    local pressed = self._closePressed
    self._closePressed = false
    if pressed and self:_isInClose(px, py) then
        self:close()
    end
end

--- Updates hover state for the current pointer position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Alert:onHoverMove(px, py)
    self._closeHover = self:_isInClose(px, py)
end

--- Clears hover state when the pointer leaves.
function Alert:onHoverEnd()
    self._closeHover = false
    Widgets.Widget.onHoverEnd(self)
end

--- Only the close button claims hover. The banner body is inert, so hover
--- passes through to whatever is drawn underneath it, matching click routing.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this widget's parent.
--- @param oy number Origin Y of this widget's parent.
--- @return PallidAlert|nil hovered The alert when the close button is hovered.
function Alert:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:_isInClose(px, py) then
        return nil
    end
    return self
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Alert:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local alpha = 1
    if self.animated then
        alpha = self.entry.alpha
        if self._closing then
            alpha = alpha * self.outro.alpha
        end
    end
    x = x + self:_shiftX()

    local fill = setTint(self._fillTint, self:shade(self.fill), alpha)
    local border = setTint(self._borderTint, self:shade(self.borderColor), alpha)

    Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, fill)
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, border)

    if self.showIcon and self.iconSize > 0 then
        local tint = setTint(self._iconTint, self:shade(self.iconColor), alpha)
        local iconX = x + self._iconX
        local iconY = y + self._iconY
        if self.iconTexture ~= nil then
            Pallid.UI.texture(el, self.iconTexture, iconX, iconY,
                self.iconSize, self.iconSize, tint, ICON_OPTS)
        else
            Pallid.UI.icon(el, self.iconName or self._severityIcon, iconX, iconY,
                self.iconSize, tint)
        end
    end

    if self.title ~= "" then
        local base = self.titleStyle.color
        self.titleStyle.color = Pallid.UI.Anim.alpha(self:shade(base), alpha)
        Pallid.UI.text(el, self.title, x + self._textX, y + self._titleY, self.titleStyle)
        self.titleStyle.color = base
    end

    if self.message ~= "" then
        local base = self.messageStyle.color
        self.messageStyle.color = Pallid.UI.Anim.alpha(self:shade(base), alpha)
        Pallid.UI.text(el, self.message, x + self._textX, y + self._messageY, self.messageStyle)
        self.messageStyle.color = base
    end

    if self.closable then
        local hover = self._closeHoverT
        if hover > 0.01 then
            Pallid.UI.Anim.lerpColor(self._closeBg,
                Pallid.UI.Color.transparent, Pallid.UI.Color.border, hover * 0.5)
            self._closeBg.a = self._closeBg.a * alpha
            Pallid.UI.roundedRect(el, x + self._closeX, y + self._closeY,
                self.closeSize, self.closeSize, 4, self._closeBg)
        end

        Pallid.UI.Anim.lerpColor(self._closeTint,
            Pallid.UI.Color.textMuted, Pallid.UI.Color.primaryStrong, hover)
        self._closeTint.a = self._closeTint.a * alpha
        local iconSize = self.closeSize * 0.6
        Pallid.UI.icon(el, ICONS.close,
            x + self._closeX + (self.closeSize - iconSize) * 0.5,
            y + self._closeY + (self.closeSize - iconSize) * 0.5,
            iconSize, self._closeTint)
    end
end
