require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
local ValueField = require "pallid/ui/widgets/internal/value_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local KNOB_RADIUS = 6
local TRACK_THICKNESS = 6
local BUBBLE_HOLD = 2.5
local BUBBLE_FADE = 10
local BUBBLE_LIFT = 15
local LABEL_GAP = 12

--- Draws one short tick across the track.
--- @param el ISUIElement Target element.
--- @param vertical boolean True for a vertical slider.
--- @param x number Tick center X.
--- @param y number Tick center Y.
--- @param size number Tick length in pixels.
--- @param color PallidColor Tick color.
local function drawTick(el, vertical, x, y, size, color)
    local half = size * 0.5
    if vertical then
        Pallid.UI.line(el, x - half, y, x + half, y, 1, color)
    else
        Pallid.UI.line(el, x, y - half, x, y + half, 1, color)
    end
end

--- Numeric slider. Horizontal sliders show a value bubble above the thumb and
--- the min/max values beside the track ends, level with the track; vertical ones
--- show the bubble above the thumb. Both grow upward.
--- @class PallidSlider : PallidWidget
--- @field value number Current value.
--- @field min number Minimum value.
--- @field max number Maximum value.
--- @field step number Snap step; 0 keeps continuous values.
--- @field vertical boolean True for a vertical slider.
--- @field showValue boolean Enables the value bubble and min/max labels.
--- @field format string string.format pattern used for values.
--- @field dragging boolean True while the knob is dragged.
--- @field grabT number Grab offset along the track, in normalized units.
--- @field tickCount integer Number of equal tick marks; 0 disables them.
--- @field tickValues table|nil Explicit tick values; overrides `tickCount` when set.
--- @field tickSize number Tick length in pixels.
--- @field tickColor PallidColor Tick colour.
--- @field onChange fun(slider: PallidSlider, value: number)|nil Callback after a value change.
local Slider = Widgets.class("Slider")

--- Creates a new `Slider` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Slider content and behaviour.
--- @field opts.vertical boolean|nil True for a vertical slider.
--- @field opts.min number|nil Minimum value, defaults to 0.
--- @field opts.max number|nil Maximum value, defaults to 1.
--- @field opts.value number|nil Initial value, defaults to min.
--- @field opts.step number|nil Snap step, defaults to 0 (continuous).
--- @field opts.showValue boolean|nil Enables the value bubble and min/max labels.
--- @field opts.format string|nil string.format pattern, defaults to "%.0f".
--- @field opts.ticks number|table|nil Equal tick count, or explicit tick values.
--- @field opts.tickSize number|nil Tick length in pixels, defaults to 4.
--- @field opts.tickColor PallidColor|nil Tick colour, defaults to textDisabled.
--- @field opts.onChange fun(slider: PallidSlider, value: number)|nil Callback after a value change.
--- @return PallidSlider slider New slider instance.
function Slider.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Slider)
    self:init(x, y, w, h)

    self.vertical = opts.vertical or false
    self.min = opts.min or 0
    self.max = opts.max or 1
    if self.max <= self.min then
        self.max = self.min + 1
    end
    self.step = opts.step or 0
    self.value = self:snap(opts.value or self.min)
    self.onChange = opts.onChange
    self.showValue = opts.showValue or false
    self.format = opts.format or "%.0f"
    self.dragging = false
    self.grabT = 0
    self.tickCount = type(opts.ticks) == "number" and math.max(0, math.floor(opts.ticks)) or 0
    self.tickValues = type(opts.ticks) == "table" and opts.ticks or nil
    self.tickSize = math.max(1, opts.tickSize or 4)
    self.tickColor = opts.tickColor or Pallid.UI.Color.textDisabled

    self.grooveColor = Pallid.UI.Color.border
    self.fillColor = Pallid.UI.Color.primary
    self.bubbleColor = Pallid.UI.Color.primary
    self.knobColor = Pallid.UI.Color.background
    self.knobBorder = Pallid.UI.Color.primaryStrong
    self.textColor = Pallid.UI.Color.textPrimary
    self.bubbleText = Pallid.UI.Color.background
    self.mutedColor = Pallid.UI.Color.textMuted
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "center",
        alignV = "middle",
    }
    self.mutedStyle = {
        font = Pallid.UI.Fonts.small,
        color = self.mutedColor,
        alignH = "left",
        alignV = "middle",
    }
    self.bubbleStyle = {
        font = Pallid.UI.Fonts.small,
        color = self.bubbleText,
        alignH = "center",
        alignV = "middle",
    }
    self._shownValue = nil
    self._shownFormat = nil
    self._shownText = ""
    self._valueAlpha = 0
    self._valueHold = 0
    return self
end

--- Factory shortcut for `Slider.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Slider settings; see `Slider.new`.
--- @return PallidSlider slider New slider instance.
function Widgets.slider(x, y, w, h, opts)
    return Slider.new(x, y, w, h, opts)
end

--- Clamps and snaps a value to the slider range.
--- @param value number Raw value.
--- @return number snapped Value clamped and snapped to `step`.
function Slider:snap(value)
    local clamped = value
    if clamped < self.min then
        clamped = self.min
    elseif clamped > self.max then
        clamped = self.max
    end
    if self.step > 0 then
        clamped = self.min + math.floor((clamped - self.min) / self.step + 0.5) * self.step
        if clamped > self.max then
            clamped = self.max
        end
    end
    return clamped
end

--- Sets the value and optionally notifies `onChange`.
--- @param value number New value.
--- @param silent boolean|nil True skips the callback.
--- @return PallidSlider self For chaining.
function Slider:setValue(value, silent)
    return ValueField.setValue(self, value, silent)
end

--- Returns the normalized knob position.
--- @return number t Normalized knob position, 0..1.
function Slider:getT()
    return (self.value - self.min) / (self.max - self.min)
end

--- True when the box has enough height for the static min/max labels.
--- The value bubble is an overlay and does not reserve layout space.
--- @return boolean fits True when the static labels can be drawn.
function Slider:hasValueRow()
    return self.showValue and not self.vertical and self.h >= 22
end

--- Formats a static range label, shortening large magnitudes.
--- @param value number Value to format.
--- @return string text Compact text such as "100k" or "1.25M".
function Slider:formatValue(value)
    local abs = math.abs(value)
    local divisor, suffix
    if abs >= 1e9 then
        divisor, suffix = 1e9, "B"
    elseif abs >= 1e6 then
        divisor, suffix = 1e6, "M"
    elseif abs >= 1e3 then
        divisor, suffix = 1e3, "k"
    else
        return string.format(self.format, value)
    end

    local scaled = value / divisor
    local magnitude = math.abs(scaled)
    local text
    if magnitude >= 100 then
        text = string.format("%.0f", scaled)
    elseif magnitude >= 10 then
        text = string.format("%.1f", scaled)
    else
        text = string.format("%.2f", scaled)
    end
    if string.find(text, ".", 1, true) then
        text = string.gsub(text, "0+$", "")
        text = string.gsub(text, "%.$", "")
    end
    return text .. suffix
end

--- Formats and measures the static min/max labels. Results are cached so the
--- draw path never formats or measures them on every frame.
--- @return string minText Formatted minimum.
--- @return string maxText Formatted maximum.
--- @return number minWidth Measured minimum width.
--- @return number maxWidth Measured maximum width.
function Slider:labels()
    local font = self.mutedStyle.font
    if self._labelMin == nil
        or self._labelMinValue ~= self.min
        or self._labelMaxValue ~= self.max
        or self._labelFormat ~= self.format
        or self._labelFont ~= font then
        self._labelMinValue = self.min
        self._labelMaxValue = self.max
        self._labelFormat = self.format
        self._labelFont = font
        self._labelMin = self:formatValue(self.min)
        self._labelMax = self:formatValue(self.max)
        self._labelMinW = getTextManager():MeasureStringX(font, self._labelMin)
        self._labelMaxW = getTextManager():MeasureStringX(font, self._labelMax)
    end
    return self._labelMin, self._labelMax, self._labelMinW, self._labelMaxW
end

--- Measures the static range labels.
--- @return number minWidth Width of the formatted minimum.
--- @return number maxWidth Width of the formatted maximum.
function Slider:labelWidths()
    if not self:hasValueRow() then
        return 0, 0
    end
    local _, _, minWidth, maxWidth = self:labels()
    return minWidth, maxWidth
end

-- Track geometry, shared by drawing, hit-testing and the bubble.
--- Returns the slider track rectangle.
--- @return number trackX Track left edge.
--- @return number trackY Track center Y.
--- @return number trackW Track width, or 0 for vertical sliders.
--- @return number trackH Track height, or 0 for horizontal sliders.
function Slider:trackRect()
    local x, y = self:originX(), self:originY()

    if self.vertical then
        local top = y + KNOB_RADIUS
        local bottom = y + self.h - KNOB_RADIUS
        return x + self.w * 0.5, top, 0, math.max(1, bottom - top)
    end

    local left = x + KNOB_RADIUS + 2
    local right = x + self.w - KNOB_RADIUS - 2
    local minWidth, maxWidth = self:labelWidths()
    if minWidth > 0 then
        left = x + math.max(KNOB_RADIUS + 2, minWidth + LABEL_GAP)
    end
    if maxWidth > 0 then
        right = x + self.w - math.max(KNOB_RADIUS + 2, maxWidth + LABEL_GAP)
    end
    local trackY = y + self.h * 0.5
    local width = right - left
    if width < 1 then
        -- Labels can eat the whole box on very narrow sliders; keep a valid track.
        left = x + self.w * 0.5 - 0.5
        width = 1
    end
    return left, trackY, width, 0
end

--- Returns the slider fraction at the point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return number t Normalized position along the track, 0..1.
function Slider:tFromPoint(px, py)
    local trackX, trackY, trackW, trackH = self:trackRect()
    if self.vertical then
        return 1 - (py - trackY) / trackH
    end
    return (px - trackX) / trackW
end

--- Sets the slider fraction.
--- @param t number Normalized position, 0..1.
function Slider:setT(t)
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end
    self:setValue(self.min + (self.max - self.min) * t)
end

--- Sets the slider fraction from a point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Slider:setFromPoint(px, py)
    self:setT(self:tFromPoint(px, py) + self.grabT)
end

--- Current knob center in root-local coordinates.
--- @return number x Knob center X.
--- @return number y Knob center Y.
function Slider:knobPoint()
    local trackX, trackY, trackW, trackH = self:trackRect()
    local t = self:getT()
    if self.vertical then
        return trackX, trackY + trackH * (1 - t)
    end
    return trackX + trackW * t, trackY
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function Slider:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end

    local knobX, knobY = self:knobPoint()
    local dx, dy = px - knobX, py - knobY
    local radius = KNOB_RADIUS + 3

    if dx * dx + dy * dy <= radius * radius then
        -- Keep the knob exactly under the grab point instead of snapping its
        -- center to the cursor.
        self.grabT = self:getT() - self:tFromPoint(px, py)
    else
        self.grabT = 0
        self:setFromPoint(px, py)
    end

    self.dragging = true
    return true
end

--- Handles pointer movement.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Slider:onMove(px, py)
    if self.dragging then
        self:setFromPoint(px, py)
    end
end

--- Handles a pointer release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Slider:onUp(px, py)
    self.dragging = false
    self.grabT = 0
end

--- Refreshes the value-bubble display timer on hover.
function Slider:onHoverStart()
    self._valueHold = BUBBLE_HOLD
end

--- Refreshes the value-bubble display timer while the cursor moves.
function Slider:onHoverMove()
    self._valueHold = BUBBLE_HOLD
end

--- Keeps the value bubble for a short time after the cursor leaves.
function Slider:onHoverEnd()
    Widgets.Widget.onHoverEnd(self)
end

--- Advances the value-bubble fade and hold countdown.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Slider:onAnimate(now, dt)
    local hold = self._valueHold or 0
    if self._hover then
        hold = BUBBLE_HOLD
    elseif hold > 0 then
        hold = math.max(0, hold - dt)
    end
    self._valueHold = hold

    local target = (self.showValue and (self._hover or hold > 0)) and 1 or 0
    self._valueAlpha = Widgets.approach(self._valueAlpha or 0, target, BUBBLE_FADE, dt)
end

--- Formats the value for the bubble.
--- @return string text Formatted current value.
function Slider:valueText()
    return ValueField.valueText(self)
end

--- Draws the value bubble.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param cx number Bubble center X.
--- @param cy number Bubble center Y.
--- @param text string Formatted value text.
--- @param alpha number|nil Bubble opacity, 0..1.
function Slider:drawBubble(el, cx, cy, text, alpha)
    alpha = alpha or 1
    local style = self.bubbleStyle
    local font = style.font
    local textWidth = getTextManager():MeasureStringX(font, text)
    local width = textWidth + 10
    local height = 16
    local left = self:originX() + 1
    local right = self:originX() + self.w - width - 1
    local x = math.max(left, math.min(cx - width * 0.5, right))
    local y = cy - height * 0.5

    Pallid.UI.roundedRect(el, x, y, width, height, 4,
        Pallid.UI.Anim.alpha(self:shade(self.bubbleColor), alpha))
    local base = style.color
    style.color = Pallid.UI.Anim.alpha(self:shade(self.bubbleText), alpha)
    Pallid.UI.text(el, text, x + width * 0.5, y + height * 0.5, style)
    style.color = base
end

--- Draws the compact value label.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param text string Small label text.
--- @param x number Anchor X.
--- @param y number Anchor Y.
--- @param alignH string Horizontal anchor.
function Slider:drawSmall(el, text, x, y, alignH)
    local style = self.mutedStyle
    style.alignH = alignH
    local base = style.color
    style.color = self:shade(self.mutedColor)
    Pallid.UI.text(el, text, x, y, style)
    style.color = base
end

--- Draws tick marks along the track. `tickValues` takes precedence over
--- `tickCount` when both are configured.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param trackX number Track left or center X.
--- @param trackY number Track top or center Y.
--- @param trackW number Track width; 0 for vertical sliders.
--- @param trackH number Track height; 0 for horizontal sliders.
function Slider:drawTicks(el, trackX, trackY, trackW, trackH)
    local color = self:shade(self.tickColor)
    local size = self.tickSize
    local span = self.max - self.min

    if self.tickValues ~= nil then
        for i = 1, #self.tickValues do
            local t = (self.tickValues[i] - self.min) / span
            if t >= 0 and t <= 1 then
                if self.vertical then
                    drawTick(el, true, trackX, trackY + trackH * (1 - t), size, color)
                else
                    drawTick(el, false, trackX + trackW * t, trackY, size, color)
                end
            end
        end
        return
    end

    if self.tickCount < 2 then
        return
    end
    for i = 1, self.tickCount do
        local t = (i - 1) / (self.tickCount - 1)
        if self.vertical then
            drawTick(el, true, trackX, trackY + trackH * (1 - t), size, color)
        else
            drawTick(el, false, trackX + trackW * t, trackY, size, color)
        end
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Slider:drawSelf(el)
    local trackX, trackY, trackW, trackH = self:trackRect()
    local t = self:getT()
    local thickness = TRACK_THICKNESS
    local knobX, knobY = self:knobPoint()
    local valueRow = self:hasValueRow()
    local minText, maxText
    if valueRow then
        minText, maxText = self:labels()
    end

    if self.vertical then
        Pallid.UI.roundedRect(el, trackX - thickness * 0.5, trackY, thickness, trackH, thickness * 0.5,
            self:shade(self.grooveColor))
        local fillH = trackH * t
        if fillH > 0 then
            Pallid.UI.roundedRect(el, trackX - thickness * 0.5, trackY + trackH - fillH, thickness, fillH,
                thickness * 0.5, self:shade(self.fillColor))
        end
        self:drawTicks(el, trackX, trackY, 0, trackH)
        Pallid.UI.circle(el, knobX, knobY, KNOB_RADIUS, self:shade(self.knobBorder))
        Pallid.UI.circle(el, knobX, knobY, KNOB_RADIUS - 1, self:shade(self.knobColor))
        if self._valueAlpha > 0.01 then
            local bubbleY = knobY - KNOB_RADIUS - BUBBLE_LIFT
            self:drawBubble(el, trackX, bubbleY, self:valueText(), self._valueAlpha)
        end
        return
    end

    Pallid.UI.roundedRect(el, trackX, trackY - thickness * 0.5, trackW, thickness, thickness * 0.5,
        self:shade(self.grooveColor))
    local fillW = trackW * t
    if fillW > 0 then
        Pallid.UI.roundedRect(el, trackX, trackY - thickness * 0.5, fillW, thickness, thickness * 0.5,
            self:shade(self.fillColor))
    end
    self:drawTicks(el, trackX, trackY, trackW, 0)
    Pallid.UI.circle(el, knobX, knobY, KNOB_RADIUS, self:shade(self.knobBorder))
    Pallid.UI.circle(el, knobX, knobY, KNOB_RADIUS - 1, self:shade(self.knobColor))

    if self._valueAlpha > 0.01 then
        local bubbleY = trackY - KNOB_RADIUS - BUBBLE_LIFT
        self:drawBubble(el, knobX, bubbleY, self:valueText(), self._valueAlpha)
    end
    if valueRow then
        self:drawSmall(el, minText, self:originX() + 2, trackY, "left")
        self:drawSmall(el, maxText, self:originX() + self.w - 2, trackY, "right")
    end
end
