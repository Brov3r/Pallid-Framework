require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
local ValueField = require "pallid/ui/widgets/internal/value_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Rotary knob / dial for bounded numeric values. Drag vertically, drag
--- horizontally or scroll the wheel; arrow keys work when the knob has focus.
--- The value arc, pointer and optional centre label are painted without
--- allocating in `drawSelf`.
--- @class PallidKnob : PallidWidget
--- @field value number Current value.
--- @field min number Minimum value.
--- @field max number Maximum value.
--- @field step number Snap step; 0 keeps continuous values.
--- @field startAngle number Arc start in degrees.
--- @field endAngle number Arc end in degrees.
--- @field thickness number Arc thickness in pixels.
--- @field tickCount integer Number of equal radial tick marks; 0 disables them.
--- @field tickValues table|nil Explicit tick values; overrides `tickCount` when set.
--- @field tickSize number Tick length in pixels.
--- @field tickColor PallidColor Tick colour.
--- @field dragging boolean True while the pointer is captured.
--- @field onChange fun(knob: PallidKnob, value: number)|nil Value callback.
--- @field acceptsFocus boolean True enables keyboard adjustment.
local Knob = Widgets.class("Knob")

--- Creates a new `Knob` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param size number Diameter in pixels.
--- @param opts table|nil Range and appearance.
--- @field opts.min number|nil Minimum value, defaults to 0.
--- @field opts.max number|nil Maximum value, defaults to 100.
--- @field opts.value number|nil Initial value, defaults to min.
--- @field opts.step number|nil Snap step, defaults to 1.
--- @field opts.startAngle number|nil Arc start in degrees, defaults to 135.
--- @field opts.endAngle number|nil Arc end in degrees, defaults to 405.
--- @field opts.thickness number|nil Arc thickness, defaults to 12% of the size.
--- @field opts.ticks number|table|nil Equal tick count, or explicit tick values.
--- @field opts.tickSize number|nil Tick length in pixels, defaults to 5.
--- @field opts.tickColor PallidColor|nil Tick colour, defaults to textDisabled.
--- @field opts.color PallidColor|nil Value arc colour.
--- @field opts.track PallidColor|nil Track colour.
--- @field opts.showValue boolean|nil True draws the formatted value in the centre.
--- @field opts.format string|nil Value format, defaults to "%.0f".
--- @field opts.onChange fun(knob: PallidKnob, value: number)|nil Value callback.
--- @return PallidKnob knob New knob.
function Knob.new(x, y, size, opts)
    opts = opts or {}
    local self = setmetatable({}, Knob)
    size = math.max(24, size or 56)
    self:init(x, y, size, size)
    self.size = size
    self.min = opts.min or 0
    self.max = opts.max or 100
    if self.max <= self.min then
        self.max = self.min + 1
    end
    self.step = math.max(0, opts.step or 1)
    self.value = self:snap(opts.value ~= nil and opts.value or self.min)
    self.startAngle = opts.startAngle or 135
    self.endAngle = opts.endAngle or 405
    if self.endAngle <= self.startAngle then
        self.endAngle = self.startAngle + 1
    end
    self.thickness = math.max(2, opts.thickness or math.max(3, math.floor(size * 0.12)))
    self.tickCount = type(opts.ticks) == "number" and math.max(0, math.floor(opts.ticks)) or 0
    self.tickValues = type(opts.ticks) == "table" and opts.ticks or nil
    self.tickSize = math.max(1, opts.tickSize or 5)
    self.tickColor = opts.tickColor or Pallid.UI.Color.textDisabled
    self.color = opts.color or Pallid.UI.Color.primary
    self.track = opts.track or Pallid.UI.Color.border
    self.showValue = opts.showValue ~= false
    self.format = opts.format or "%.0f"
    self.onChange = opts.onChange
    self.dragging = false
    self._dragStartX = 0
    self._dragStartY = 0
    self._dragStartValue = self.value
    self.acceptsFocus = true

    self.valueStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "center",
        alignV = "middle",
    }
    self._shownValue = nil
    self._shownFormat = nil
    self._shownText = ""
    return self
end

--- Factory shortcut for `Knob.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param size number Diameter in pixels.
--- @param opts table|nil Range and appearance; see `Knob.new`.
--- @return PallidKnob knob New knob.
function Widgets.knob(x, y, size, opts)
    return Knob.new(x, y, size, opts)
end

--- Clamps and snaps a value to the knob range.
--- @param value number Raw value.
--- @return number value Clamped and snapped value.
function Knob:snap(value)
    local snapped = math.max(self.min, math.min(self.max, value or self.min))
    if self.step > 0 then
        local steps = math.floor((snapped - self.min) / self.step + 0.5)
        snapped = self.min + steps * self.step
        if snapped > self.max then
            snapped = self.max
        end
    end
    return snapped
end

--- Sets the value and optionally notifies `onChange`.
--- @param value number New value.
--- @param silent boolean|nil True skips the callback.
--- @return PallidKnob self For chaining.
function Knob:setValue(value, silent)
    return ValueField.setValue(self, value, silent)
end

--- Returns the current value.
--- @return number value Current value.
function Knob:getValue()
    return self.value
end

--- Returns the value normalized to the 0..1 range.
--- @return number t Normalized value, 0..1.
function Knob:getT()
    return (self.value - self.min) / (self.max - self.min)
end

--- Starts a vertical or horizontal drag.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when accepted.
function Knob:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    self.dragging = true
    self._dragStartX = px
    self._dragStartY = py
    self._dragStartValue = self.value
    return true
end

--- Applies the drag delta. The dominant axis wins: dragging up increases the
--- value, and so does dragging to the right.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Knob:onMove(px, py)
    if not self.dragging then
        return
    end
    local range = self.max - self.min
    local dx = px - self._dragStartX
    local dy = self._dragStartY - py
    local delta
    if math.abs(dx) > math.abs(dy) then
        delta = dx / 150 * range
    else
        delta = dy / 150 * range
    end
    self:setValue(self._dragStartValue + delta)
end

--- Ends the drag.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Knob:onUp(px, py)
    self.dragging = false
end

--- Adjusts the value with the wheel.
--- @param delta number Wheel steps; positive increases.
--- @return boolean handled True when consumed.
function Knob:onWheel(delta)
    if not self.enabled then
        return false
    end
    local step = self.step > 0 and self.step or (self.max - self.min) * 0.02
    self:setValue(self.value + delta * step)
    return true
end

--- Keyboard adjustment.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when consumed.
function Knob:onKeyPress(key)
    if not self.enabled or Keyboard == nil then
        return false
    end
    local step = self.step > 0 and self.step or (self.max - self.min) * 0.02
    if key == Keyboard.KEY_UP or key == Keyboard.KEY_RIGHT then
        self:setValue(self.value + step)
        return true
    end
    if key == Keyboard.KEY_DOWN or key == Keyboard.KEY_LEFT then
        self:setValue(self.value - step)
        return true
    end
    if key == Keyboard.KEY_HOME then
        self:setValue(self.min)
        return true
    end
    if key == Keyboard.KEY_END then
        self:setValue(self.max)
        return true
    end
    return false
end

--- Returns the formatted text of the current value.
--- @return string text Formatted current value.
function Knob:valueText()
    return ValueField.valueText(self)
end

--- Returns the unit-circle offset for an angle.
--- @param angle number Angle in radians.
--- @return number x Offset from the centre.
--- @return number y Offset from the centre.
function Knob:_pointAt(angle)
    return math.cos(angle), math.sin(angle)
end

--- Draws optional radial tick marks at the configured value positions.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param cx number Knob centre X.
--- @param cy number Knob centre Y.
--- @param radius number Arc radius in pixels.
function Knob:drawTicks(el, cx, cy, radius)
    local color = self:shade(self.tickColor)
    local inner = radius - self.tickSize * 0.5
    local outer = radius + self.tickSize * 0.5
    local startRad = math.rad(self.startAngle)
    local spanRad = math.rad(self.endAngle - self.startAngle)

    if self.tickValues ~= nil then
        local range = self.max - self.min
        for i = 1, #self.tickValues do
            local t = (self.tickValues[i] - self.min) / range
            if t >= 0 and t <= 1 then
                local dx, dy = self:_pointAt(startRad + spanRad * t)
                Pallid.UI.line(el, cx + dx * inner, cy + dy * inner,
                    cx + dx * outer, cy + dy * outer, 1, color)
            end
        end
        return
    end

    if self.tickCount < 2 then
        return
    end
    for i = 1, self.tickCount do
        local t = (i - 1) / (self.tickCount - 1)
        local dx, dy = self:_pointAt(startRad + spanRad * t)
        Pallid.UI.line(el, cx + dx * inner, cy + dy * inner,
            cx + dx * outer, cy + dy * outer, 1, color)
    end
end

--- Paints the dial.
--- @param el ISUIElement Host element the tree is rendered into.
function Knob:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local radius = self.size * 0.5
    local cx, cy = x + radius, y + radius
    local arcRadius = math.max(1, radius - self.thickness * 0.5)
    local startRad = math.rad(self.startAngle)
    local endRad = math.rad(self.endAngle)
    local t = self:getT()

    Pallid.UI.ring(el, cx, cy, arcRadius, self.thickness, self:shade(self.track), startRad, endRad)
    self:drawTicks(el, cx, cy, arcRadius)
    if t > 0 then
        Pallid.UI.ring(
            el,
            cx,
            cy,
            arcRadius,
            self.thickness,
            self:shade(self.color),
            startRad,
            startRad + (endRad - startRad) * t
        )
    end

    Pallid.UI.circle(el, cx, cy, math.max(2, arcRadius - self.thickness * 0.5 - 1), self:shade(Pallid.UI.Color.background))
    Pallid.UI.circle(
        el,
        cx,
        cy,
        math.max(1, arcRadius - self.thickness * 0.5 - 3),
        self:shade(Pallid.UI.Color.surfaceElevated)
    )

    local angle = startRad + (endRad - startRad) * t
    local dx, dy = self:_pointAt(angle)
    local inner = math.max(0, arcRadius - self.thickness - 2)
    local outer = arcRadius + 1
    Pallid.UI.line(
        el,
        cx + dx * inner,
        cy + dy * inner,
        cx + dx * outer,
        cy + dy * outer,
        2,
        self:shade(Pallid.UI.Color.primaryStrong)
    )

    if self.showValue then
        self.valueStyle.color = self:shade(Pallid.UI.Color.textPrimary)
        Pallid.UI.text(el, self:valueText(), cx, cy, self.valueStyle)
    end
end

--- Returns the preferred size.
--- @param maxW number|nil Available width.
--- @param maxH number|nil Available height.
--- @return number width Preferred width.
--- @return number height Preferred height.
function Knob:preferredSize(maxW, maxH)
    local size = math.min(maxW or self.size, maxH or self.size)
    return size, size
end
