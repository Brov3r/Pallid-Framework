require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/widgets/widget"
local addOptionListMethods = require "pallid/ui/widgets/optionlist"
local SelectionSet = require "pallid/ui/widgets/internal/selection_set"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local DEFAULT_SOUND = "UIToggleTickBox"

--- Multi-select list. The marker is a square check box, visually distinct from
--- the radio circles used by RadioGroup. Input is pointer-only for now.
--- @class PallidToggleGroup : PallidWidget
--- @field options (string|table)[] Raw options in caller order.
--- @field items PallidOption[] Normalised options used for drawing and callbacks.
--- @field selected table<integer, boolean> Checked options keyed by index.
--- @field onChange fun(group: PallidToggleGroup, index: integer, checked: boolean, label: string, item: PallidOption)|nil Toggle callback.
--- @field rowHeight number Row height in pixels.
--- @field markerSize number Marker diameter in pixels.
--- @field hoverRow integer Hovered row, or 0.
--- @field hover number Eased hover strength, 0..1.
local ToggleGroup = Widgets.class("ToggleGroup")
addOptionListMethods(ToggleGroup)

--- Creates a new `ToggleGroup` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param options (string|table)[] Option labels or `{ label, value, icon, disabled }` tables.
--- @param opts table|nil Shared option-list settings.
--- @field opts.selected integer[]|nil Initially checked 1-based indexes.
--- @field opts.rowHeight number|nil Row height, defaults to 22.
--- @field opts.font UIFont|string|nil Label font or a Pallid.UI.Fonts key.
--- @field opts.onChange fun(group: PallidToggleGroup, index: integer, checked: boolean, label: string, item: PallidOption)|nil Toggle callback.
--- @field opts.sound string|false|nil Sound name; false or "" silences it.
--- @return PallidToggleGroup group New toggle group.
function ToggleGroup.new(x, y, w, options, opts)
    opts = opts or {}
    local self = setmetatable({}, ToggleGroup)
    self.selected = {}
    self.markerShape = "square"
    self.defaultSound = DEFAULT_SOUND
    self:init(x, y, w, 0)
    self:_setupOptionList(options, opts)

    if type(opts.selected) == "table" then
        for _, index in ipairs(opts.selected) do
            self:setSelected(index, true, true)
        end
    elseif opts.selected ~= nil then
        Pallid.log("ToggleGroup: opts.selected must be a table of indexes")
    end
    return self
end

--- Factory shortcut for `ToggleGroup.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param options (string|table)[] Option labels or tables.
--- @param opts table|nil Shared option-list settings.
--- @return PallidToggleGroup group New toggle group.
function Widgets.toggleGroup(x, y, w, options, opts)
    return ToggleGroup.new(x, y, w, options, opts)
end

--- Removes checked indexes that no longer exist or became disabled.
function ToggleGroup:_clampSelection()
    SelectionSet.clamp(self)
end

--- Returns true when an option is in the selected set.
--- @param index integer Option index.
--- @return boolean checked True when the option is checked.
function ToggleGroup:_isRowChecked(index)
    return self.selected[index] == true
end

--- Toggles one option and reports that the state changed.
--- @param index integer Option index.
--- @return boolean changed True when the option state changed.
function ToggleGroup:_activateRow(index)
    local checked = not self:isSelected(index)
    self:setSelected(index, checked)
    return true
end

--- Changes one option. `checked` is coerced to boolean and invalid indexes are
--- ignored. Disabled options cannot be checked.
--- @param index integer 1-based option index.
--- @param checked boolean New state.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidToggleGroup self For chaining.
function ToggleGroup:setSelected(index, checked, silent)
    checked = checked == true
    if not self:_validIndex(index) then
        Pallid.log("ToggleGroup:setSelected expects an index inside the option list")
        return self
    end

    local item = self.items[index]
    if checked and item.disabled then
        return self
    end
    if self:isSelected(index) == checked then
        return self
    end

    if checked then
        self.selected[index] = true
    else
        self.selected[index] = nil
    end
    if not silent and self.onChange ~= nil then
        self.onChange(self, index, checked, item.label, item)
    end
    return self
end

--- Checks or clears every enabled option.
--- @param checked boolean New state for all enabled options.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidToggleGroup self For chaining.
function ToggleGroup:setAll(checked, silent)
    SelectionSet.setAll(self, checked, silent)
    return self
end

--- Clears every checked option.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidToggleGroup self For chaining.
function ToggleGroup:clear(silent)
    return self:setAll(false, silent)
end

--- Returns true when the item is selected.
--- @param index integer Option index.
--- @return boolean checked True when the option is checked.
function ToggleGroup:isSelected(index)
    return self.selected[index] == true
end

--- Returns the selected item.
--- @return integer[] indexes Checked 1-based indexes in ascending order.
function ToggleGroup:getSelected()
    local result = {}
    for i = 1, #self.items do
        if self.selected[i] then
            result[#result + 1] = i
        end
    end
    return result
end

--- Returns the number of selected items.
--- @return integer count Number of checked options.
function ToggleGroup:getSelectedCount()
    local count = 0
    for i = 1, #self.items do
        if self.selected[i] then
            count = count + 1
        end
    end
    return count
end


