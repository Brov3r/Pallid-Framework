require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/popup_select"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local PopupSelect = Widgets.PopupSelect
local OptionUtil = require "pallid/ui/widgets/internal/option_util"

local ICON = 14
local ICON_GAP = 6
local SIDE_PAD = 8
local CHECK = 12
local ICON_OPTS = { mode = "fit" }

--- Closed field with the selected value and an arrow. The popup list is drawn
--- by the root overlay and shares geometry, clipping and scrolling with
--- MultiSelect through `PallidPopupSelect`.
--- @class PallidDropdown : PallidPopupSelect
--- @field selected integer 1-based selected option, or 0 when nothing is selected.
--- @field placeholder string Text shown when nothing is selected.
--- @field onChange fun(dropdown: PallidDropdown, index: integer, value: any, item: PallidOption)|nil Called when the selection changes.
local Dropdown = Widgets.class("Dropdown", PopupSelect)

--- Creates a new `Dropdown` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[] Option labels or `{ label, value, icon, disabled }` tables.
--- @param opts table|nil Appearance and behaviour.
--- @field opts.selected integer|nil Initial 1-based selection; 0 means none.
--- @field opts.placeholder string|nil Placeholder text, defaults to "Select...".
--- @field opts.maxHeight number|nil Maximum popup height, defaults to 220.
--- @field opts.itemHeight number|nil Popup row height, defaults to 22.
--- @field opts.font UIFont|string|nil Font or a Pallid.UI.Fonts key.
--- @field opts.sound string|false|nil Click sound; false or "" silences it.
--- @field opts.onChange fun(dropdown: PallidDropdown, index: integer, value: any, item: PallidOption)|nil Selection callback.
--- @field opts.onOpen fun(dropdown: PallidDropdown)|nil Called after opening.
--- @field opts.onClose fun(dropdown: PallidDropdown)|nil Called after closing.
--- @return PallidDropdown dropdown New dropdown instance.
function Dropdown.new(x, y, w, h, options, opts)
    opts = opts or {}
    local self = setmetatable({}, Dropdown)
    self.selected = 0
    self:init(x, y, w, h)
    self.placeholder = opts.placeholder or "Select..."
    self.onChange = opts.onChange
    self:_initPopupSelect(options, opts)
    self:setSelected(opts.selected or 0, true)
    return self
end

--- Factory shortcut for `Dropdown.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[] Option labels or tables.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidDropdown dropdown New dropdown instance.
function Widgets.dropdown(x, y, w, h, options, opts)
    return Dropdown.new(x, y, w, h, options, opts)
end

--- Returns the selected item.
--- @return integer index Selected 1-based option, or 0 when none is selected.
function Dropdown:getSelected()
    return self.selected
end

--- Returns the selected item.
--- @return PallidOption|nil item Selected option descriptor, or nil.
function Dropdown:getSelectedItem()
    return self.items[self.selected]
end

--- Returns the selected option.
--- @return string|nil label Selected option label, or nil.
function Dropdown:getSelectedOption()
    local item = self.items[self.selected]
    return item ~= nil and item.label or nil
end

--- Returns the selected value.
--- @return any value Selected option value, or nil.
function Dropdown:getSelectedValue()
    local item = self.items[self.selected]
    return item ~= nil and item.value or nil
end

--- Returns true when the item is selected.
--- @param index integer Option index.
--- @return boolean selected True when the option is selected.
function Dropdown:isSelected(index)
    return self.selected == index
end

--- Selects an option. Invalid indexes are ignored; 0 or nil clears the field.
--- @param index integer|nil New 1-based selection, or 0/nil to clear.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidDropdown self For chaining.
function Dropdown:setSelected(index, silent)
    if index == nil then
        index = 0
    end
    if index == 0 then
        return self:clearSelection(silent)
    end
    if not self:_validIndex(index) then
        Pallid.log("Dropdown:setSelected expects an index inside the option list")
        return self
    end
    if self.items[index].disabled or index == self.selected then
        return self
    end

    self.selected = index
    self:_refreshFieldLayout()
    if not silent and self.onChange ~= nil then
        local item = self.items[index]
        self.onChange(self, index, item.value, item)
    end
    return self
end

--- Clears the selected option.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidDropdown self For chaining.
function Dropdown:clearSelection(silent)
    if self.selected == 0 then
        return self
    end
    self.selected = 0
    self:_refreshFieldLayout()
    if not silent and self.onChange ~= nil then
        self.onChange(self, 0, nil, nil)
    end
    return self
end

--- Returns the row that should start highlighted in the list.
--- @return integer|nil index Valid index.
function Dropdown:_initialHighlight()
    return self.selected ~= 0 and self.selected or 0
end

--- Selects a row, notifies the change callback and closes the list.
--- @param index integer Option index.
function Dropdown:_activateRow(index)
    if self:_rowDisabled(index) then
        return
    end
    local item = self.items[index]
    local changed = index ~= self.selected
    self.selected = index
    self:_refreshFieldLayout()
    if changed and self.onChange ~= nil then
        self.onChange(self, index, item.value, item)
    end
    self:close()
end

--- Returns true when the row is the current selection.
--- @param index integer Option index.
--- @return boolean checked True for the selected option.
function Dropdown:_isRowChecked(index)
    return self.selected == index
end

--- Keeps the selection valid after options or disabled flags change.
function Dropdown:_clampSelection()
    if self.selected == 0 then
        return
    end
    local item = self.items[self.selected]
    if item == nil or item.disabled then
        self.selected = 0
    end
end

--- Rebuilds the cached field label.
function Dropdown:_refreshFieldLayout()
    local item = self.items[self.selected]
    local text = item ~= nil and item.label or self.placeholder
    local iconSlot = item ~= nil and item.hasIcon and (ICON + ICON_GAP) or 0
    self._fieldIcon = item
    self._fieldIconSlot = iconSlot
    self._fieldLabel = Pallid.UI.truncateText(
        text,
        self.style.font,
        math.max(0, self.w - SIDE_PAD * 2 - 20 - iconSlot)
    )
end

--- Draws the icon and label shown in the closed field.
--- @param el ISUIElement Host element.
--- @param x number Field left.
--- @param y number Field top.
function Dropdown:_drawFieldContent(el, x, y)
    local item = self._fieldIcon
    if item ~= nil and item.hasIcon then
        OptionUtil.drawIcon(
            el,
            item,
            x + SIDE_PAD,
            y + (self.h - ICON) * 0.5,
            ICON,
            self:shade(self.style.color)
        )
    end

    local base = self.style.color
    self.style.color = self:shade(
        item == nil and Pallid.UI.Color.textDisabled or base
    )
    Pallid.UI.text(
        el,
        self._fieldLabel or "",
        x + SIDE_PAD + (self._fieldIconSlot or 0),
        y + self.h * 0.5,
        self.style
    )
    self.style.color = base
end

--- Draws the check marker for the selected row.
--- @param el ISUIElement Host element.
--- @param item PallidOption Row item.
--- @param index integer Row index.
--- @param x number Marker left.
--- @param y number Marker top.
function Dropdown:_drawListMarker(el, item, index, x, y)
    if self:_isRowChecked(index) and self._checkTexture ~= nil then
        Pallid.UI.texture(
            el,
            self._checkTexture,
            x,
            y,
            CHECK,
            CHECK,
            self:shade(self.checkColor),
            ICON_OPTS
        )
    end
end
