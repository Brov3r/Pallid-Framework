require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/popup_select"
local SelectionSet = require "pallid/ui/widgets/internal/selection_set"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local PopupSelect = Widgets.PopupSelect

local CHECK = 12
local CHIP_HEIGHT = 16
local CHIP_GAP = 4
local CHIP_PADDING = 6
local SIDE_PAD = 8
local FIELD_RIGHT_RESERVE = 26
local ICON_OPTS = { mode = "fit" }

--- Multi-select popup with chips in the field. The popup stays open while
--- toggling values; chips are measured only when options, selection, font or
--- bounds change.
--- @class PallidMultiSelect : PallidPopupSelect
--- @field selected table<integer, boolean> Checked options keyed by index.
--- @field onChange fun(multi: PallidMultiSelect, index: integer, checked: boolean, item: PallidOption)|nil Called after an option is toggled.
local MultiSelect = Widgets.class("MultiSelect", PopupSelect)

--- Creates a new `MultiSelect` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[] Option labels or `{ label, value, icon, disabled }` tables.
--- @param opts table|nil Appearance and behaviour.
--- @field opts.selected integer[]|nil Initially selected indexes.
--- @field opts.placeholder string|nil Empty-field text, defaults to "None selected".
--- @field opts.maxHeight number|nil Maximum popup height, defaults to 220.
--- @field opts.itemHeight number|nil Popup row height, defaults to 22.
--- @field opts.font UIFont|string|nil Font or a Pallid.UI.Fonts key.
--- @field opts.sound string|false|nil Click sound; false or "" silences it.
--- @field opts.onChange fun(multi: PallidMultiSelect, index: integer, checked: boolean, item: PallidOption)|nil Toggle callback.
--- @field opts.onOpen fun(multi: PallidMultiSelect)|nil Called after opening.
--- @field opts.onClose fun(multi: PallidMultiSelect)|nil Called after closing.
--- @return PallidMultiSelect multi New multi-select instance.
function MultiSelect.new(x, y, w, h, options, opts)
    opts = opts or {}
    local self = setmetatable({}, MultiSelect)
    self.selected = {}
    self:init(x, y, w, h)
    self.placeholder = opts.placeholder or "None selected"
    self.onChange = opts.onChange
    self.chipFill = Pallid.UI.Color.primarySoft
    if opts.sound == nil then
        opts.sound = "UIToggleTickBox"
    end
    self:_initPopupSelect(options, opts)

    if type(opts.selected) == "table" then
        for _, index in ipairs(opts.selected) do
            self:setSelected(index, true, true)
        end
    end
    self:_refreshFieldLayout()
    return self
end

--- Factory shortcut for `MultiSelect.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[] Option labels or tables.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidMultiSelect multi New multi-select instance.
function Widgets.multiSelect(x, y, w, h, options, opts)
    return MultiSelect.new(x, y, w, h, options, opts)
end

--- Returns the selected item.
--- @return integer[] indexes Selected 1-based indexes in ascending order.
function MultiSelect:getSelected()
    local result = {}
    for i = 1, #self.items do
        if self:isSelected(i) then
            result[#result + 1] = i
        end
    end
    return result
end

--- Returns the selected options.
--- @return string[] labels Selected option labels.
function MultiSelect:getSelectedOptions()
    local result = {}
    for i = 1, #self.items do
        if self:isSelected(i) then
            result[#result + 1] = self.items[i].label
        end
    end
    return result
end

--- Returns the number of selected items.
--- @return integer count Number of selected options.
function MultiSelect:getSelectedCount()
    local count = 0
    for i = 1, #self.items do
        if self:isSelected(i) then
            count = count + 1
        end
    end
    return count
end

--- Returns true when the item is selected.
--- @param index integer Option index.
--- @return boolean selected True when the option is selected.
function MultiSelect:isSelected(index)
    return self.selected[index] == true
end

--- Changes one option. `checked` is coerced to boolean and invalid indexes are
--- ignored. Disabled options cannot be selected.
--- @param index integer 1-based option index.
--- @param checked boolean New state.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidMultiSelect self For chaining.
function MultiSelect:setSelected(index, checked, silent)
    checked = checked == true
    if not self:_validIndex(index) then
        Pallid.log("MultiSelect:setSelected expects an index inside the option list")
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
    self:_refreshFieldLayout()
    if not silent and self.onChange ~= nil then
        self.onChange(self, index, checked, item)
    end
    return self
end

--- Checks or clears every enabled option.
--- @param checked boolean New state for all enabled options.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidMultiSelect self For chaining.
function MultiSelect:setAll(checked, silent)
    SelectionSet.setAll(self, checked, silent)
    return self
end

--- Clears every selected option.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidMultiSelect self For chaining.
function MultiSelect:clear(silent)
    return self:setAll(false, silent)
end

--- Toggles the checked state of an option row.
--- @param index integer Option index.
function MultiSelect:_activateRow(index)
    self:setSelected(index, not self:isSelected(index))
end

--- Tells whether an option row is checked.
--- @param index integer Option index.
--- @return boolean checked True for a checked option.
function MultiSelect:_isRowChecked(index)
    return self:isSelected(index)
end

--- Removes invalid or disabled selected indexes.
function MultiSelect:_clampSelection()
    SelectionSet.clamp(self)
end

--- Rebuilds the cached chip layout. This is the only place that measures chip
--- text; draw only paints the cached result.
function MultiSelect:_refreshFieldLayout()
    local manager = getTextManager()
    local font = self.style.font
    self._chipHeight = math.min(CHIP_HEIGHT, math.max(4, self.h - 2))
    local right = self.w - SIDE_PAD - FIELD_RIGHT_RESERVE
    local maxWidth = math.max(0, right - SIDE_PAD)

    local indices = {}
    local widths = {}
    for i = 1, #self.items do
        if self:isSelected(i) then
            indices[#indices + 1] = i
            widths[#widths + 1] = manager:MeasureStringX(font, self.items[i].label) + CHIP_PADDING * 2
        end
    end

    local total = #indices
    local count = total
    local used = 0
    while count > 0 do
        used = 0
        for k = 1, count do
            used = used + widths[k] + (k > 1 and CHIP_GAP or 0)
        end
        if used <= maxWidth then
            break
        end
        count = count - 1
    end

    self._chipLayout = {}
    for k = 1, count do
        self._chipLayout[k] = {
            text = self.items[indices[k]].label,
            width = widths[k],
        }
    end

    self._moreText = nil
    self._moreOffset = 0
    if count < total then
        local more = "+" .. (total - count)
        local moreW = manager:MeasureStringX(font, more)
        while count > 0 and used + 2 + moreW > maxWidth do
            count = count - 1
            used = 0
            for k = 1, count do
                used = used + widths[k] + (k > 1 and CHIP_GAP or 0)
            end
            self._chipLayout[count + 1] = nil
            more = "+" .. (total - count)
            moreW = manager:MeasureStringX(font, more)
        end
        self._moreText = Pallid.UI.truncateText(more, font, math.max(0, maxWidth - used - 2))
        self._moreOffset = used + 2
    end
end

--- Draws the check marker of an option row in the popup list.
--- @param el ISUIElement Host element.
--- @param item PallidOption Row item.
--- @param index integer Row index.
--- @param x number Marker left.
--- @param y number Marker top.
function MultiSelect:_drawListMarker(el, item, index, x, y)
    local checked = self:_isRowChecked(index)
    Pallid.UI.roundedRect(
        el,
        x,
        y,
        CHECK,
        CHECK,
        2,
        self:shade(checked and self.chipFill or self.markerFill)
    )
    Pallid.UI.roundedBorder(el, x, y, CHECK, CHECK, 2, 1, self:shade(self.markerBorder))
    if checked and self._checkTexture ~= nil then
        local size = CHECK * 0.8
        Pallid.UI.texture(
            el,
            self._checkTexture,
            x + (CHECK - size) * 0.5,
            y + (CHECK - size) * 0.5,
            size,
            size,
            self:shade(self.checkColor),
            ICON_OPTS
        )
    end
end

--- Draws the selected chips, or the placeholder when nothing is selected.
--- @param el ISUIElement Host element.
--- @param x number Field left.
--- @param y number Field top.
function MultiSelect:_drawFieldContent(el, x, y)
    local chips = self._chipLayout or {}
    if #chips == 0 and self._moreText == nil then
        local base = self.style.color
        self.style.color = self:shade(Pallid.UI.Color.textDisabled)
        Pallid.UI.text(el, self.placeholder, x + SIDE_PAD, y + self.h * 0.5, self.style)
        self.style.color = base
        return
    end

    local chipH = self._chipHeight or CHIP_HEIGHT
    local chipY = y + (self.h - chipH) * 0.5
    local chipX = x + SIDE_PAD
    local base = self.style.color
    for i = 1, #chips do
        local chip = chips[i]
        Pallid.UI.roundedRect(
            el,
            chipX,
            chipY,
            chip.width,
            chipH,
            chipH * 0.5,
            self:shade(self.chipFill)
        )
        self.style.color = self:shade(self.checkColor)
        Pallid.UI.text(el, chip.text, chipX + CHIP_PADDING, chipY + chipH * 0.5, self.style)
        chipX = chipX + chip.width + CHIP_GAP
    end
    if self._moreText ~= nil then
        self.style.color = self:shade(base)
        Pallid.UI.text(
            el,
            self._moreText,
            x + SIDE_PAD + self._moreOffset,
            y + self.h * 0.5,
            self.style
        )
    end
    self.style.color = base
end

--- Replaces shared popup colours and the chip fill.
--- @param colors table Keys from `PopupSelect:setColors` plus `chip`.
--- @return PallidMultiSelect self For chaining.
function MultiSelect:setColors(colors)
    PopupSelect.setColors(self, colors)
    colors = colors or {}
    if colors.chip ~= nil then
        self.chipFill = colors.chip
    end
    return self
end
