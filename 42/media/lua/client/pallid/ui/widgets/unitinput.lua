require "pallid/ui/internal"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/combobox"
require "pallid/ui/widgets/inputtext"
local ValueField = require "pallid/ui/widgets/internal/value_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local UNIT_W = 82
local GAP = 4

--- Numeric input with a configurable unit selector. Values are stored in base
--- units; each unit descriptor provides the factor to convert back to base.
--- @class PallidUnitInput : PallidWidget
--- @field value number Value in base units.
--- @field units table[] Normalised unit descriptors.
--- @field unitIndex integer Selected unit index.
--- @field input PallidInputText Numeric field.
--- @field unitCombo PallidComboBox Unit selector.
--- @field onChange fun(field: PallidUnitInput, value: number, number: number, unit: table)|nil Change callback.
local UnitInput = Widgets.class("UnitInput")

--- Creates a new `UnitInput` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Value and unit settings.
--- @field opts.value number|nil Initial value in base units, defaults to 0.
--- @field opts.units table|nil Units: `{ key, label, factor }` or strings with factor 1.
--- @field opts.unit string|number|nil Initial unit key or unit index, defaults to the first.
--- @field opts.min number|nil Minimum base value.
--- @field opts.max number|nil Maximum base value.
--- @field opts.decimals number|nil Fractional digits, defaults to 2.
--- @field opts.onChange fun(field: PallidUnitInput, value: number, number: number, unit: table)|nil Change callback.
--- @return PallidUnitInput field New unit input.
function UnitInput.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, UnitInput)
    self:init(x, y, w or 0, h or 0)

    self.onChange = opts.onChange
    self.decimals = math.max(0, opts.decimals or 2)
    self.min = opts.min
    self.max = opts.max
    self.value = tonumber(opts.value) or 0
    self.units = {}
    self:setUnits(opts.units, opts.unit, true)

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

    self.unitCombo = Widgets.comboBox(0, 0, UNIT_W, self.h, self:_unitLabels(), {
        onChange = function(_, _, index)
            if index ~= nil and self.units[index] ~= nil then
                self.unitIndex = index
                self:_refreshText()
                self:_emit()
            end
        end,
    })
    self.unitCombo:setValue(self.units[self.unitIndex] and self.units[self.unitIndex].label or nil, true)
    self:add(self.unitCombo)

    self:layout()
    self:_refreshText()
    return self
end

--- Factory shortcut for `UnitInput.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Value and unit settings; see `UnitInput.new`.
--- @return PallidUnitInput field New unit input.
function Widgets.unitInput(x, y, w, h, opts)
    return UnitInput.new(x, y, w, h, opts)
end

--- @return string[] labels Unit labels in order.
function UnitInput:_unitLabels()
    local labels = {}
    for i = 1, #self.units do
        labels[i] = self.units[i].label
    end
    return labels
end

--- Replaces the units.
--- @param units table|nil Unit definitions; nil restores one unit named "unit".
--- @param unit string|integer|nil Initial unit key or index.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidUnitInput self For chaining.
function UnitInput:setUnits(units, unit, silent)
    self.units = {}
    local source = type(units) == "table" and units or nil
    if source == nil or #source == 0 then
        self.units[1] = { key = "unit", label = "unit", factor = 1 }
    else
        for i = 1, #source do
            local entry = source[i]
            if type(entry) == "table" then
                self.units[i] = {
                    key    = tostring(entry.key or entry.label or i),
                    label  = tostring(entry.label or entry.key or i),
                    factor = tonumber(entry.factor) or 1,
                }
            else
                self.units[i] = { key = tostring(entry), label = tostring(entry), factor = 1 }
            end
        end
    end

    self.unitIndex = 1
    if type(unit) == "number" then
        self.unitIndex = math.max(1, math.min(#self.units, math.floor(unit)))
    elseif unit ~= nil then
        for i = 1, #self.units do
            if self.units[i].key == unit or self.units[i].label == unit then
                self.unitIndex = i
                break
            end
        end
    end

    if self.unitCombo ~= nil then
        self.unitCombo:setOptions(self:_unitLabels())
        self.unitCombo:setValue(self.units[self.unitIndex] and self.units[self.unitIndex].label or nil, true)
        self:_refreshText()
    end
    if not silent then
        self:_emit()
    end
    return self
end

--- @return table unit Selected unit descriptor.
function UnitInput:getUnit()
    return self.units[self.unitIndex]
end

--- Changes the selected unit without changing the base value.
--- @param unit string|integer Unit key or one-based index.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidUnitInput self For chaining.
function UnitInput:setUnit(unit, silent)
    local index = type(unit) == "number" and math.floor(unit) or nil
    if index == nil then
        for i = 1, #self.units do
            if self.units[i].key == unit or self.units[i].label == unit then
                index = i
                break
            end
        end
    end
    if index == nil or self.units[index] == nil then
        return self
    end
    self.unitIndex = index
    if self.unitCombo ~= nil then
        self.unitCombo:setValue(self.units[index].label, true)
        self:_refreshText()
    end
    if not silent then
        self:_emit()
    end
    return self
end

--- @return number factor Selected unit factor.
function UnitInput:_factor()
    local unit = self.units[self.unitIndex]
    return unit ~= nil and unit.factor or 1
end

--- Formats a visible number.
--- @param number number Visible number.
--- @return string text Trimmed text.
function UnitInput:_format(number)
    return ValueField.format(self.decimals, number)
end

--- Refreshes the visible text from the base value.
function UnitInput:_refreshText()
    self.input:setText(self:_format(self.value / self:_factor()), true)
end

--- Reads the field and updates the base value.
function UnitInput:_readInput()
    local number = tonumber(self.input:getText())
    if number == nil then
        return
    end
    local value = number * self:_factor()
    local clamped = false
    if self.min ~= nil and value < self.min then
        value = self.min
        clamped = true
    end
    if self.max ~= nil and value > self.max then
        value = self.max
        clamped = true
    end
    self.value = value
    if clamped then
        self:_refreshText()
    end
    self:_emit()
end

--- Sets the base value.
--- @param value number New base value.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidUnitInput self For chaining.
function UnitInput:setValue(value, silent)
    value = tonumber(value) or 0
    if self.min ~= nil and value < self.min then
        value = self.min
    end
    if self.max ~= nil and value > self.max then
        value = self.max
    end
    self.value = value
    self:_refreshText()
    if not silent then
        self:_emit()
    end
    return self
end

--- @return number value Base value.
function UnitInput:getValue()
    return self.value
end

--- Positions the input and the unit selector.
function UnitInput:layout()
    ValueField.layout(self, UNIT_W, GAP)
end

--- Resizes the widget.
--- @param x number New offset X.
--- @param y number New offset Y.
--- @param w number New width.
--- @param h number New height.
--- @return PallidUnitInput self For chaining.
function UnitInput:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- Emits the change callback.
function UnitInput:_emit()
    if self.onChange ~= nil then
        self.onChange(self, self.value, self.value / self:_factor(), self.units[self.unitIndex])
    end
end

--- Enables or disables both controls.
--- @param enabled boolean New state.
--- @return PallidUnitInput self For chaining.
function UnitInput:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    self.input:setEnabled(enabled)
    self.unitCombo:setEnabled(enabled)
    return self
end

--- Returns the preferred size.
--- @param maxW number|nil Available width.
--- @param maxH number|nil Available height.
--- @return number width Preferred width.
--- @return number height Preferred height.
function UnitInput:preferredSize(maxW, maxH)
    return maxW or math.max(150, self.w), math.max(22, self.h)
end
