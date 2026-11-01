require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/slider"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local Slider = Widgets.Slider
local KNOB_RADIUS = 6
local TRACK_THICKNESS = 6
local BUBBLE_LIFT = 20

--- Slider with two thumbs that pick an interval. It inherits the geometry,
--- colours and value-bubble behaviour from `PallidSlider`; only the two-value
--- interaction and the second thumb are added here.
--- @class PallidRangeSlider : PallidSlider
--- @field low number Lower selected value.
--- @field high number Upper selected value.
--- @field active "low"|"high"|nil Thumb currently being dragged.
--- @field grabT number Grab offset along the track, in normalized units.
--- @field onChange fun(slider: PallidRangeSlider, low: number, high: number)|nil Callback after a value change.
local RangeSlider = Widgets.class("RangeSlider", Slider)

--- Creates a new `RangeSlider` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Range content and behaviour.
--- @field opts.min number|nil Minimum value, defaults to 0.
--- @field opts.max number|nil Maximum value, defaults to 100.
--- @field opts.low number|nil Initial low value, defaults to min.
--- @field opts.high number|nil Initial high value, defaults to max.
--- @field opts.step number|nil Snap step, defaults to 0.
--- @field opts.showValue boolean|nil Enables the value bubbles and min/max labels.
--- @field opts.format string|nil string.format pattern, defaults to "%.0f".
--- @field opts.onChange fun(slider: PallidRangeSlider, low: number, high: number)|nil Callback after a value change.
--- @return PallidRangeSlider slider New range slider instance.
function RangeSlider.new(x, y, w, h, opts)
    opts = opts or {}
    local sliderOpts = {}
    for key, value in pairs(opts) do
        sliderOpts[key] = value
    end
    sliderOpts.max = opts.max or 100
    sliderOpts.vertical = false

    local self = setmetatable(Slider.new(x, y, w, h, sliderOpts), RangeSlider)
    self.vertical = false
    self.low = self:snap(opts.low or self.min)
    self.high = self:snap(opts.high or self.max)
    if self.high < self.low then
        self.low, self.high = self.high, self.low
    end
    self.active = nil
    self.grabT = 0
    self.bubbleText = Pallid.UI.Color.surface
    self.bubbleStyle.color = self.bubbleText
    self._shownLow = nil
    self._shownHigh = nil
    self._shownFormat = nil
    self._textLow = ""
    self._textHigh = ""
    return self
end

--- Factory shortcut for `RangeSlider.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Range settings; see `RangeSlider.new`.
--- @return PallidRangeSlider slider New range slider instance.
function Widgets.rangeSlider(x, y, w, h, opts)
    return RangeSlider.new(x, y, w, h, opts)
end

--- Returns the track left edge in root-local coordinates.
--- @return number left Track left edge.
function RangeSlider:trackLeft()
    local left = self:trackRect()
    return left
end

--- Returns the usable track width.
--- @return number width Track width in pixels.
function RangeSlider:trackWidth()
    local _, _, width = self:trackRect()
    return width
end

--- Returns the track center Y in root-local coordinates.
--- @return number y Track center Y.
function RangeSlider:trackY()
    local _, y = self:trackRect()
    return y
end

--- Maps the slider position to its value.
--- @param value number Value inside the selected range.
--- @return number t Normalized track position, 0..1.
function RangeSlider:tOf(value)
    return (value - self.min) / (self.max - self.min)
end

--- Returns the slider fraction at the point.
--- @param px number Cursor X in root-local coordinates.
--- @return number t Normalized track position, 0..1.
function RangeSlider:tFromPoint(px)
    local left, _, width = self:trackRect()
    return (px - left) / width
end

--- Maps the slider position to its value.
--- @param t number Normalized position, 0..1.
--- @return number value Snapped value at the position.
function RangeSlider:valueOf(t)
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end
    return self:snap(self.min + (self.max - self.min) * t)
end

--- Sets both values and keeps them ordered.
--- @param low number New lower value.
--- @param high number New upper value.
--- @param silent boolean|nil True skips the callback.
--- @return PallidRangeSlider self For chaining.
function RangeSlider:setValues(low, high, silent)
    local newLow = self:snap(math.min(low, high))
    local newHigh = self:snap(math.max(low, high))
    if newLow == self.low and newHigh == self.high then
        return self
    end
    self.low = newLow
    self.high = newHigh
    if not silent and self.onChange ~= nil then
        self.onChange(self, self.low, self.high)
    end
    return self
end

--- Starts dragging the nearest thumb or jumps a thumb to the clicked track point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function RangeSlider:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end

    local left, y, width = self:trackRect()
    local radius = KNOB_RADIUS + 3
    local lowX = left + width * self:tOf(self.low)
    local highX = left + width * self:tOf(self.high)
    local lowDistance = (px - lowX) * (px - lowX) + (py - y) * (py - y)
    local highDistance = (px - highX) * (px - highX) + (py - y) * (py - y)

    if lowDistance <= radius * radius and lowDistance <= highDistance then
        self.active = "low"
        self.grabT = self:tOf(self.low) - self:tFromPoint(px)
    elseif highDistance <= radius * radius then
        self.active = "high"
        self.grabT = self:tOf(self.high) - self:tFromPoint(px)
    elseif lowDistance <= highDistance then
        self.active = "low"
        self.grabT = 0
        self.low = self:valueOf(self:tFromPoint(px))
    else
        self.active = "high"
        self.grabT = 0
        self.high = self:valueOf(self:tFromPoint(px))
    end

    self:setValues(self.low, self.high)
    return true
end

--- Moves the active thumb while keeping the range ordered.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function RangeSlider:onMove(px, py)
    if self.active == nil or not self.enabled then
        return
    end
    local value = self:valueOf(self:tFromPoint(px) + self.grabT)
    if self.active == "low" then
        self.low = math.min(value, self.high)
    else
        self.high = math.max(value, self.low)
    end
    self:setValues(self.low, self.high)
end

--- Finishes a thumb drag.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function RangeSlider:onUp(px, py)
    self.active = nil
    self.grabT = 0
end

--- Formats the value for the bubble.
--- @param value number Value to format.
--- @param isLow boolean True formats the low value.
--- @return string text Formatted value text.
function RangeSlider:valueText(value, isLow)
    if isLow then
        if value ~= self._shownLow or self.format ~= self._shownFormat then
            self._shownLow = value
            self._shownFormat = self.format
            self._textLow = string.format(self.format, value)
        end
        return self._textLow
    end
    if value ~= self._shownHigh or self.format ~= self._shownFormat then
        self._shownHigh = value
        self._shownFormat = self.format
        self._textHigh = string.format(self.format, value)
    end
    return self._textHigh
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function RangeSlider:drawSelf(el)
    local left, y, width = self:trackRect()
    local lowT = self:tOf(self.low)
    local highT = self:tOf(self.high)
    local lowX = left + width * lowT
    local highX = left + width * highT

    Pallid.UI.roundedRect(el, left, y - TRACK_THICKNESS * 0.5, width, TRACK_THICKNESS,
        TRACK_THICKNESS * 0.5, self:shade(self.grooveColor))
    local fillW = width * (highT - lowT)
    if fillW > 0 then
        Pallid.UI.roundedRect(el, lowX, y - TRACK_THICKNESS * 0.5, fillW, TRACK_THICKNESS,
            TRACK_THICKNESS * 0.5, self:shade(self.fillColor))
    end

    Pallid.UI.circle(el, lowX, y, KNOB_RADIUS, self:shade(self.knobBorder))
    Pallid.UI.circle(el, lowX, y, KNOB_RADIUS - 1, self:shade(self.knobColor))
    Pallid.UI.circle(el, highX, y, KNOB_RADIUS, self:shade(self.knobBorder))
    Pallid.UI.circle(el, highX, y, KNOB_RADIUS - 1, self:shade(self.knobColor))

    if self._valueAlpha > 0.01 then
        local bubbleY = y - KNOB_RADIUS - BUBBLE_LIFT
        self:drawBubble(el, lowX, bubbleY, self:valueText(self.low, true), self._valueAlpha)
        self:drawBubble(el, highX, bubbleY, self:valueText(self.high, false), self._valueAlpha)
    end

    if self:hasValueRow() then
        self:drawSmall(el, self:formatValue(self.min), self:originX() + 2, y, "left")
        self:drawSmall(el, self:formatValue(self.max), self:originX() + self.w - 2, y, "right")
    end
end
