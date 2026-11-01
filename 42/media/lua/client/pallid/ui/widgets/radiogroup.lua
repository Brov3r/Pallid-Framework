require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/widgets/widget"
local addOptionListMethods = require "pallid/ui/widgets/optionlist"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local DEFAULT_SOUND = "UISelectListItem"

--- Vertical list of options with a single selection. The marker is a radio
--- circle, visually distinct from the square check used by ToggleGroup.
--- Input is pointer-only for now.
--- @class PallidRadioGroup : PallidWidget
--- @field options (string|table)[] Raw options in caller order.
--- @field items PallidOption[] Normalised options used for drawing and callbacks.
--- @field selected integer 1-based selected option, or 0 when nothing is selected.
--- @field onChange fun(group: PallidRadioGroup, index: integer, label: string|nil, item: PallidOption|nil)|nil Selection callback; index is 0 on clear.
--- @field rowHeight number Row height in pixels.
--- @field markerSize number Marker diameter in pixels.
--- @field hoverRow integer Hovered row, or 0.
--- @field hover number Eased hover strength, 0..1.
local RadioGroup = Widgets.class("RadioGroup")
addOptionListMethods(RadioGroup)

--- Creates a new `RadioGroup` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param options (string|table)[] Option labels or `{ label, value, icon, disabled }` tables.
--- @param opts table|nil Shared option-list settings.
--- @field opts.selected integer|nil Initial 1-based selection; 0 or nil means none.
--- @field opts.rowHeight number|nil Row height, defaults to 22.
--- @field opts.font UIFont|string|nil Label font or a Pallid.UI.Fonts key.
--- @field opts.onChange fun(group: PallidRadioGroup, index: integer, label: string|nil, item: PallidOption|nil)|nil Selection callback.
--- @field opts.sound string|false|nil Sound name; false or "" silences it.
--- @return PallidRadioGroup group New radio group.
function RadioGroup.new(x, y, w, options, opts)
    opts = opts or {}
    local self = setmetatable({}, RadioGroup)
    self.selected = 0
    self.markerShape = "circle"
    self.defaultSound = DEFAULT_SOUND
    self:init(x, y, w, 0)
    self:_setupOptionList(options, opts)
    self:setSelected(opts.selected or 0, true)
    return self
end

--- Factory shortcut for `RadioGroup.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param options (string|table)[] Option labels or tables.
--- @param opts table|nil Shared option-list settings.
--- @return PallidRadioGroup group New radio group.
function Widgets.radioGroup(x, y, w, options, opts)
    return RadioGroup.new(x, y, w, options, opts)
end

--- Clamps the selected index after the option list changes.
function RadioGroup:_clampSelection()
    if self.selected == 0 then
        return
    end
    local item = self.items[self.selected]
    if item == nil or item.disabled then
        self.selected = 0
    end
end

--- @param index integer Option index.
--- @return boolean checked True when the option is selected.
function RadioGroup:_isRowChecked(index)
    return self.selected == index
end

--- @param index integer Option index.
--- @return boolean changed True when the selection changed.
function RadioGroup:_activateRow(index)
    local item = self.items[index]
    if item == nil or item.disabled or index == self.selected then
        return false
    end
    self.selected = index
    if self.onChange ~= nil then
        self.onChange(self, index, item.label, item)
    end
    return true
end

--- Selects an option. Invalid indexes are ignored; 0 or nil clears the
--- selection. Disabled options cannot be selected.
--- @param index integer|nil New 1-based selection, or 0/nil to clear.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidRadioGroup self For chaining.
function RadioGroup:setSelected(index, silent)
    if index == nil then
        index = 0
    end
    if index == 0 then
        return self:clearSelection(silent)
    end
    if not self:_validIndex(index) then
        Pallid.log("RadioGroup:setSelected expects an index inside the option list")
        return self
    end
    if self.items[index].disabled or index == self.selected then
        return self
    end

    self.selected = index
    if not silent and self.onChange ~= nil then
        local item = self.items[index]
        self.onChange(self, index, item.label, item)
    end
    return self
end

--- Clears the current selection.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidRadioGroup self For chaining.
function RadioGroup:clearSelection(silent)
    if self.selected == 0 then
        return self
    end
    self.selected = 0
    if not silent and self.onChange ~= nil then
        self.onChange(self, 0, nil, nil)
    end
    return self
end

--- Returns the selected item.
--- @return integer index Selected 1-based option, or 0 when none is selected.
function RadioGroup:getSelected()
    return self.selected
end

--- Returns true when the item is selected.
--- @param index integer Option index.
--- @return boolean selected True when the option is selected.
function RadioGroup:isSelected(index)
    return self.selected == index
end

--- Returns the selected option.
--- @return string|nil label Selected option label, or nil.
function RadioGroup:getSelectedOption()
    local item = self.items[self.selected]
    return item ~= nil and item.label or nil
end
