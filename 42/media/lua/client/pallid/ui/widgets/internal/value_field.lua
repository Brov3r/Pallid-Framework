require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Shared helpers for numeric fields, unit fields and sliders. Kept in one
--- place so DurationInput, UnitInput, Slider and Knob do not carry duplicated
--- layout and formatting code.
--- @class PallidValueFieldUtil
local ValueField = {}

--- Positions a numeric input and its unit combo.
--- @param field table Owner with `input`, `unitCombo`, `w` and `h`.
--- @param unitWidth number Unit selector width.
--- @param gap number Gap between the field and the selector.
function ValueField.layout(field, unitWidth, gap)
    local inputW = math.max(40, field.w - unitWidth - gap)
    field.input:setBounds(0, 0, inputW, field.h)
    field.unitCombo:setBounds(inputW + gap, 0, unitWidth, field.h)
end

--- Formats a number and trims trailing zeroes.
--- @param decimals number Maximum fractional digits.
--- @param number number Value to format.
--- @return string text Trimmed text.
function ValueField.format(decimals, number)
    local text = string.format("%." .. decimals .. "f", number)
    text = string.gsub(text, "0+$", "")
    text = string.gsub(text, "%.$", "")
    return text
end

--- Clamps, snaps and stores a numeric widget value.
--- @param widget table Slider or Knob-like instance.
--- @param value number New value.
--- @param silent boolean|nil True skips `onChange`.
--- @return table widget The same widget.
function ValueField.setValue(widget, value, silent)
    local snapped = widget:snap(value)
    if snapped == widget.value then
        return widget
    end
    widget.value = snapped
    if not silent and widget.onChange ~= nil then
        widget.onChange(widget, snapped)
    end
    return widget
end

--- Returns the cached formatted value for a slider/knob-like widget.
--- @param widget table Owner with `value`, `format` and `_shown*` cache fields.
--- @return string text Formatted value.
function ValueField.valueText(widget)
    if widget.value ~= widget._shownValue or widget.format ~= widget._shownFormat then
        widget._shownValue = widget.value
        widget._shownFormat = widget.format
        widget._shownText = string.format(widget.format, widget.value)
    end
    return widget._shownText
end

--- Resizes a child list to the owner bounds.
--- @param owner table Owner with a `list` field.
--- @param w number New width.
--- @param h number New height.
function ValueField.resizeChild(owner, w, h)
    if owner.list ~= nil then
        owner.list:setBounds(0, 0, w, h)
    end
end

return ValueField
