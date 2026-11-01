require "pallid/ui/internal"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/combobox"
require "pallid/ui/widgets/inputtext"
local ValueField = require "pallid/ui/widgets/internal/value_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local UNIT_W = 76
local GAP = 4

--- Duration field: a numeric input with a unit selector. The widget stores and
--- returns seconds; the visible number is expressed in the selected unit.
--- @class PallidDurationInput : PallidWidget
--- @field value number Duration in seconds.
--- @field unit string Selected unit key.
--- @field input PallidInputText Numeric field.
--- @field unitCombo PallidComboBox Unit selector.
--- @field factors table<string, number> Unit-to-seconds factors.
--- @field onChange fun(field: PallidDurationInput, seconds: number, number: number, unit: string)|nil Change callback.
local DurationInput = Widgets.class("DurationInput")

--- Creates a new `DurationInput` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Range and unit settings.
--- @field opts.value number|nil Initial duration in seconds, defaults to 0.
--- @field opts.unit string|nil Initial unit, defaults to "s".
--- @field opts.units table|nil Unit keys, defaults to `{ "ms", "s", "min", "h" }`.
--- @field opts.min number|nil Minimum duration in seconds.
--- @field opts.max number|nil Maximum duration in seconds.
--- @field opts.decimals number|nil Visible fractional digits, defaults to 3.
--- @field opts.onChange fun(field: PallidDurationInput, seconds: number, number: number, unit: string)|nil Change callback.
--- @return PallidDurationInput input New duration field.
function DurationInput.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, DurationInput)
    self:init(x, y, w or 0, h or 0)

    self.factors = {
        ms  = 0.001,
        s   = 1,
        min = 60,
        h   = 3600,
        d   = 86400,
    }
    self.unitKeys = type(opts.units) == "table" and opts.units or { "ms", "s", "min", "h" }
    self.unit = opts.unit or "s"
    self.min = opts.min
    self.max = opts.max
    self.decimals = math.max(0, opts.decimals or 3)
    self.onChange = opts.onChange
    self.value = tonumber(opts.value) or 0

    self.input = Widgets.inputText(0, 0, 1, self.h, {
        numeric  = true,
        decimals = self.decimals,
        onChange = function()
            self:_readInput()
        end,
        onSubmit = function()
            self:_readInput()
        end,
    })
    self:add(self.input)

    self.unitCombo = Widgets.comboBox(0, 0, UNIT_W, self.h, self.unitKeys, {
        onChange = function(_, value)
            if value ~= nil and self.factors[value] ~= nil then
                self.unit = value
                self:_refreshText()
                self:_emit()
            end
        end,
    })
    self.unitCombo:setValue(self.unit, true)
    self:add(self.unitCombo)

    self:layout()
    self:_refreshText()
    return self
end

--- Factory shortcut for `DurationInput.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Range and unit settings; see `DurationInput.new`.
--- @return PallidDurationInput input New duration field.
function Widgets.durationInput(x, y, w, h, opts)
    return DurationInput.new(x, y, w, h, opts)
end

--- Positions the input and the unit selector.
function DurationInput:layout()
    ValueField.layout(self, UNIT_W, GAP)
end

--- Resizes the field.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidDurationInput self For chaining.
function DurationInput:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- @return number factor Seconds per selected unit.
function DurationInput:_factor()
    return self.factors[self.unit] or 1
end

--- @param number number Visible numeric value.
--- @return string text Trimmed decimal text.
function DurationInput:_format(number)
    return ValueField.format(self.decimals, number)
end

--- Refreshes the visible text from the stored seconds.
function DurationInput:_refreshText()
    local number = self.value / self:_factor()
    self.input:setText(self:_format(number), true)
end

--- Reads the numeric field and updates the value in seconds.
function DurationInput:_readInput()
    local number = tonumber(self.input:getText())
    if number == nil then
        return
    end
    local seconds = number * self:_factor()
    if self.min ~= nil and seconds < self.min then
        seconds = self.min
        self:_setSeconds(seconds)
    elseif self.max ~= nil and seconds > self.max then
        seconds = self.max
        self:_setSeconds(seconds)
    end
    self.value = seconds
    self:_emit()
end

--- Updates the stored seconds and the visible text.
--- @param seconds number New duration.
function DurationInput:_setSeconds(seconds)
    self.value = seconds
    self:_refreshText()
end

--- Sets the duration in seconds.
--- @param seconds number New duration in seconds.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidDurationInput self For chaining.
function DurationInput:setValue(seconds, silent)
    seconds = tonumber(seconds) or 0
    if self.min ~= nil and seconds < self.min then
        seconds = self.min
    end
    if self.max ~= nil and seconds > self.max then
        seconds = self.max
    end
    self.value = seconds
    self:_refreshText()
    if not silent then
        self:_emit()
    end
    return self
end

--- @return number seconds Current duration in seconds.
function DurationInput:getValue()
    return self.value
end

--- Changes the display unit without changing the duration.
--- @param unit string New unit key.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidDurationInput self For chaining.
function DurationInput:setUnit(unit, silent)
    if self.factors[unit] ~= nil then
        self.unit = unit
        self.unitCombo:setValue(unit, true)
        self:_refreshText()
        if not silent then
            self:_emit()
        end
    end
    return self
end

--- @return string unit Current unit key.
function DurationInput:getUnit()
    return self.unit
end

--- Emits the change callback.
function DurationInput:_emit()
    if self.onChange ~= nil then
        self.onChange(self, self.value, self.value / self:_factor(), self.unit)
    end
end

--- Enables or disables both controls.
--- @param enabled boolean New state.
--- @return PallidDurationInput self For chaining.
function DurationInput:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    self.input:setEnabled(enabled)
    self.unitCombo:setEnabled(enabled)
    return self
end

--- Returns the preferred width and current height.
--- @param maxW number|nil Available width.
--- @param maxH number|nil Available height.
--- @return number width Preferred width.
--- @return number height Preferred height.
function DurationInput:preferredSize(maxW, maxH)
    return maxW or math.max(140, self.w), math.max(22, self.h)
end
