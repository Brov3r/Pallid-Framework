require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/panel"
require "pallid/ui/widgets/popover"
require "pallid/ui/widgets/inputtext"
require "pallid/ui/widgets/virtuallist"
local normaliseOption = require "pallid/ui/widgets/internal/option_item"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"
local PopupCombo = require "pallid/ui/widgets/internal/popup_combo"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }
local ROW_HEIGHT = 22
local FILTER_HEIGHT = 22
local FILTER_GAP = 4
local POPOVER_PAD = 4
local CHECK_SIZE = 12
local CHECK_GAP = 6

--- Searchable multi-select dropdown. The field summarises the selection; the
--- popover contains a filter input and a virtualised list with checkboxes.
--- Clicking a row toggles it without closing the popover, while Enter/Escape
--- close it.
--- @class PallidMultiSelectComboBox : PallidWidget
--- @field items PallidOption[] Normalised options.
--- @field selected table<integer, boolean> Selected raw indexes as a set.
--- @field filterText string Current filter text.
--- @field open boolean True while the popover is visible.
--- @field filterInput PallidInputText Filter field inside the popover.
--- @field list PallidVirtualList Option list with single-row highlight and custom check rendering.
--- @field popover PallidPopover Popover that owns the filter and list.
--- @field onChange fun(combo: PallidMultiSelectComboBox, values: any[], indexes: integer[])|nil Selection callback.
--- @field onFilter fun(combo: PallidMultiSelectComboBox, text: string)|nil Filter callback.
local MultiCombo = Widgets.class("MultiSelectComboBox")

--- Creates a new `MultiSelectComboBox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[]|nil Option list.
--- @param opts table|nil Behaviour and appearance.
--- @field opts.placeholder string|nil Field text shown when nothing is selected.
--- @field opts.selected integer[]|nil Initially selected one-based indexes.
--- @field opts.filter string|fun(item: PallidOption, text: string): boolean|nil Initial filter or predicate.
--- @field opts.onChange fun(combo: PallidMultiSelectComboBox, values: any[], indexes: integer[])|nil Selection callback.
--- @field opts.onFilter fun(combo: PallidMultiSelectComboBox, text: string)|nil Filter callback.
--- @field opts.maxHeight number|nil Maximum list height, defaults to 200.
--- @field opts.filterPlaceholder string|nil Filter field placeholder.
--- @return PallidMultiSelectComboBox combo New multi-select combo.
function MultiCombo.new(x, y, w, h, options, opts)
    opts = opts or {}
    local self = setmetatable({}, MultiCombo)
    self:init(x, y, w or 0, h or 0)

    self.placeholder = opts.placeholder
    self.onChange = opts.onChange
    self.onFilter = opts.onFilter
    self.maxHeight = math.max(ROW_HEIGHT, math.floor(opts.maxHeight or 200))
    self.rowHeight = ROW_HEIGHT
    self.open = false
    self.filterText = ""
    self.selected = {}
    self.items = {}
    self._filtered = {}
    self._arrowTexture = Pallid.UI.Textures.get(ICON_DIR .. "arrow-down-04.png")
    self._checkTexture = Pallid.UI.Textures.get(ICON_DIR .. "tick.png")
    self._clearTexture = Pallid.UI.Textures.get(ICON_DIR .. "cross.png")
    self._pollUp = false
    self._pollDown = false
    self._pollReturn = false
    self._pollEscape = false
    self._summaryCount = -1
    self._summaryFirst = nil
    self._summaryText = ""

    self.style = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.rowStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.text,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }

    if type(opts.filter) == "function" then
        self.filterFn = opts.filter
    elseif type(opts.filter) == "string" then
        self.filterText = opts.filter
    end

    self:setOptions(options, true)

    local content = Widgets.panel(0, 0, 1, 1)
    content.hittable = false
    self.content = content

    self.filterInput = Widgets.inputText(0, 0, 1, FILTER_HEIGHT, {
        text = self.filterText,
        placeholder = opts.filterPlaceholder or Pallid.UI.translate("UI_Pallid_Filter", "Filter..."),
        background = Pallid.UI.Color.surfaceMuted,
        border = Pallid.UI.Color.border,
        radius = 3,
        paddingX = 6,
        paddingY = 2,
        onChange = function(_, text)
            self:_applyFilter(text, true)
        end,
        onKeyPress = function(_, key)
            return self:_onFilterKey(key)
        end,
    })
    content:add(self.filterInput)

    self.list = Widgets.virtualList(0, FILTER_HEIGHT + FILTER_GAP, 1, 1, {
        itemCount     = 0,
        rowHeight     = ROW_HEIGHT,
        selectionMode = "single",
        onSelect      = function(_, index)
            self:_toggleFiltered(index)
        end,
        render        = function(el, index, rowX, rowY, rowW, rowH, state)
            self:_drawRow(el, index, rowX, rowY, rowW, rowH, state)
        end,
    })
    content:add(self.list)

    self.popover = Widgets.popover(content, {
        width = math.max(1, self.w),
        height = FILTER_HEIGHT + FILTER_GAP + ROW_HEIGHT + POPOVER_PAD * 2,
        padding = POPOVER_PAD,
        offset = 2,
        radius = 4,
        onClose = function()
            if self.open then
                self.open = false
                self.filterInput:blur()
            end
        end,
    })

    if type(opts.selected) == "table" then
        self:setSelectedIndexes(opts.selected, true)
    end
    self:_applyFilter(self.filterText, false)
    return self
end

--- Factory shortcut for `MultiCombo.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[]|nil Option list.
--- @param opts table|nil Behaviour and appearance; see `MultiCombo.new`.
--- @return PallidMultiSelectComboBox combo New multi-select combo.
function Widgets.multiSelectComboBox(x, y, w, h, options, opts)
    return MultiCombo.new(x, y, w, h, options, opts)
end

--- Replaces the option list and prunes selections outside the new range.
--- @param options (string|table)[]|nil New options.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidMultiSelectComboBox self For chaining.
function MultiCombo:setOptions(options, silent)
    local list = type(options) == "table" and options or {}
    self.items = {}
    for i = 1, #list do
        self.items[i] = normaliseOption(list[i])
    end
    self._summaryCount = -1
    self._summaryFirst = nil
    for index in pairs(self.selected) do
        if index > #self.items then
            self.selected[index] = nil
        end
    end
    if self.list ~= nil then
        self:_applyFilter(self.filterText, false)
    end
    if not silent and self.onChange ~= nil then
        local values, indexes = self:getSelected()
        self.onChange(self, values, indexes)
    end
    return self
end

--- Rebuilds the filtered row index list from the current filter text.
--- @param text string|nil Filter text.
--- @param notify boolean True calls `onFilter`.
function MultiCombo:_applyFilter(text, notify)
    self.filterText = text or ""
    local filtered = self._filtered
    for i = #filtered, 1, -1 do
        filtered[i] = nil
    end

    local query = string.lower(self.filterText)
    local predicate = self.filterFn
    for i = 1, #self.items do
        local item = self.items[i]
        local label = string.lower(item.label)
        local matches = query == "" or string.find(label, query, 1, true) ~= nil
        if matches and predicate ~= nil then
            matches = predicate(item, self.filterText) ~= false
        end
        if matches then
            filtered[#filtered + 1] = i
        end
    end

    if self.list ~= nil then
        self.list:setItemCount(#filtered)
        self.list:scrollTo(0)
        self.list:setSelected(nil, true)
        self:_resizePopover()
    end
    if notify and self.onFilter ~= nil then
        self.onFilter(self, self.filterText)
    end
end

--- Resizes the popover to the filtered row count.
function MultiCombo:_resizePopover()
    PopupCombo.resize(self)
end

--- Opens the popover and focuses the filter.
--- @return PallidMultiSelectComboBox self For chaining.
function MultiCombo:show()
    PopupCombo.show(self)
    return self
end

--- Closes the popover.
--- @return PallidMultiSelectComboBox self For chaining.
function MultiCombo:close()
    if not self.open then
        return self
    end
    self.open = false
    self.filterInput:blur()
    self.popover:close()
    return self
end

--- Tells whether the popover is currently visible.
--- @return boolean open True while the popover is visible.
function MultiCombo:isOpen()
    return self.open
end

--- Toggles the filtered row under the click.
--- @param index integer One-based filtered row index.
function MultiCombo:_toggleFiltered(index)
    local rawIndex = self._filtered[index]
    if rawIndex == nil then
        return
    end
    local item = self.items[rawIndex]
    if item == nil or item.disabled then
        return
    end
    self.selected[rawIndex] = not self.selected[rawIndex] or nil
    self.list:setSelected(index, true)
    if self.onChange ~= nil then
        local values, indexes = self:getSelected()
        self.onChange(self, values, indexes)
    end
end

--- Returns the selected values and their one-based indexes.
--- @return any[] values Selected option values in option order.
--- @return integer[] indexes Selected one-based indexes in option order.
function MultiCombo:getSelected()
    local values, indexes = {}, {}
    for i = 1, #self.items do
        if self.selected[i] then
            indexes[#indexes + 1] = i
            local item = self.items[i]
            values[#values + 1] = item.value ~= nil and item.value or item.label
        end
    end
    return values, indexes
end

--- Replaces the selected indexes.
--- @param indexes integer[]|nil One-based indexes to select; nil clears.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidMultiSelectComboBox self For chaining.
function MultiCombo:setSelectedIndexes(indexes, silent)
    self.selected = {}
    if type(indexes) == "table" then
        for i = 1, #indexes do
            local index = math.floor(indexes[i])
            if index >= 1 and index <= #self.items then
                self.selected[index] = true
            end
        end
    end
    if not silent and self.onChange ~= nil then
        local values, selected = self:getSelected()
        self.onChange(self, values, selected)
    end
    return self
end

--- Counts the selected options.
--- @return integer count Number of selected options.
function MultiCombo:getSelectedCount()
    local count = 0
    for _ in pairs(self.selected) do
        count = count + 1
    end
    return count
end

--- Returns the clear-button rectangle in root-local coordinates.
--- @return number x Clear-zone left.
--- @return number y Clear-zone top.
--- @return number w Clear-zone width.
--- @return number h Clear-zone height.
function MultiCombo:clearRect()
    return self:originX() + self.w - 36, self:originY() + 2, 16, self.h - 4
end

--- Tells whether a point lies on the clear button of a non-empty field.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the point is on the clear button.
function MultiCombo:_isOverClear(px, py)
    if self:getSelectedCount() == 0 then
        return false
    end
    local x, y, w, h = self:clearRect()
    return px >= x and px < x + w and py >= y and py < y + h
end

--- Clears every selected option.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidMultiSelectComboBox self For chaining.
function MultiCombo:clearSelection(silent)
    self.selected = {}
    self._summaryCount = -1
    self._summaryFirst = nil
    if self.list ~= nil then
        self.list:setSelected(nil, true)
    end
    if not silent and self.onChange ~= nil then
        local values, indexes = self:getSelected()
        self.onChange(self, values, indexes)
    end
    return self
end

--- Polls navigation keys because native text entry suppresses OnKeyPressed.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function MultiCombo:onUpdate(now, dt)
    PopupCombo.onUpdate(self, now, dt)
end

--- Handles keys while the filter is focused.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when consumed.
function MultiCombo:_onFilterKey(key)
    if Keyboard == nil then
        return false
    end
    if key == Keyboard.KEY_UP or key == Keyboard.KEY_DOWN then
        local count = #self._filtered
        if count == 0 then
            return true
        end
        local current = self.list.selected or 0
        local nextIndex = current + (key == Keyboard.KEY_UP and -1 or 1)
        if nextIndex < 1 then
            nextIndex = 1
        elseif nextIndex > count then
            nextIndex = count
        end
        self.list:setSelected(nextIndex, true)
        self:_scrollToRow(nextIndex)
        return true
    end
    if key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER then
        self:close()
        return true
    end
    if key == Keyboard.KEY_ESCAPE then
        self:close()
        return true
    end
    return false
end

--- Scrolls the popover list so a filtered row is visible.
--- @param index integer One-based filtered row index.
function MultiCombo:_scrollToRow(index)
    PopupCombo.scrollToRow(self, index)
end

--- Draws one row with a checkbox, optional icon and label.
--- @param el ISUIElement Host element.
--- @param index integer One-based filtered row index.
--- @param x number Row left.
--- @param y number Row top.
--- @param w number Row width.
--- @param h number Row height.
--- @param state PallidVirtualRowState Reused row state.
function MultiCombo:_drawRow(el, index, x, y, w, h, state)
    local rawIndex = self._filtered[index]
    if rawIndex == nil then
        return
    end
    local item = self.items[rawIndex]
    if state.hovered then
        Pallid.UI.rect(el, x, y, w, h, self:shade(Pallid.UI.Color.accentSoft))
    end

    local checkX = x + 6
    local checkY = y + (h - CHECK_SIZE) * 0.5
    if self.selected[rawIndex] then
        Pallid.UI.roundedRect(el, checkX, checkY, CHECK_SIZE, CHECK_SIZE, 2, self:shade(Pallid.UI.Color.primarySoft))
    else
        Pallid.UI.roundedRect(el, checkX, checkY, CHECK_SIZE, CHECK_SIZE, 2, self:shade(Pallid.UI.Color.surfaceElevated))
    end
    Pallid.UI.roundedBorder(el, checkX, checkY, CHECK_SIZE, CHECK_SIZE, 2, 1, self:shade(Pallid.UI.Color.border))
    if self.selected[rawIndex] and self._checkTexture ~= nil then
        Pallid.UI.texture(
            el, self._checkTexture, checkX + 1, checkY + 1, CHECK_SIZE - 2, CHECK_SIZE - 2,
            self:shade(Pallid.UI.Color.primaryStrong), ICON_OPTS
        )
    end

    local textX = checkX + CHECK_SIZE + CHECK_GAP
    local iconSize = 14
    if item.hasIcon then
        OptionUtil.drawIcon(el, item, textX, y + (h - iconSize) * 0.5, iconSize,
            self:shade(item.disabled and Pallid.UI.Color.textDisabled or Pallid.UI.Color.text))
        textX = textX + iconSize + CHECK_GAP
    end
    local style = self.rowStyle
    style.color = self:shade(item.disabled and Pallid.UI.Color.textDisabled or Pallid.UI.Color.text)
    style.maxWidth = math.max(0, w - (textX - x) - 6)
    Pallid.UI.text(el, item.label, textX, y + h * 0.5, style)
    style.maxWidth = nil
end

--- Handles a click on the closed field.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when accepted.
function MultiCombo:onDown(px, py, button)
    if button ~= "right" and self:_isOverClear(px, py) then
        self:clearSelection()
        return true
    end
    return PopupCombo.onDown(self, button)
end

--- Closes the popover when the widget leaves the tree.
function MultiCombo:onDetach()
    if self.open then
        self.open = false
        self.popover:close()
    end
end

--- Returns the cached field summary, rebuilding it when the selection changes.
--- @return string text Field summary.
function MultiCombo:_ensureSummary()
    local count = 0
    local first = nil
    for i = 1, #self.items do
        if self.selected[i] then
            count = count + 1
            first = first or i
        end
    end
    if count == self._summaryCount and first == self._summaryFirst then
        return self._summaryText
    end
    self._summaryCount = count
    self._summaryFirst = first
    if count == 1 then
        self._summaryText = self.items[first] and self.items[first].label or ""
    elseif count > 1 then
        self._summaryText = string.format(
            Pallid.UI.translate("UI_Pallid_SelectedCount", "%d selected"),
            count
        )
    else
        self._summaryText = ""
    end
    return self._summaryText
end

--- Draws the closed field summary.
--- @param el ISUIElement Host element the tree is rendered into.
function MultiCombo:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local radius = 4
    Pallid.UI.roundedRect(el, x, y, self.w, self.h, radius, self:shade(Pallid.UI.Color.surface))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, radius, 1, self:shade(Pallid.UI.Color.border))

    local text = self:_ensureSummary()
    local muted = text == ""
    if muted then
        text = self.placeholder or ""
    end

    local count = self._summaryCount or 0
    if text ~= "" then
        local style = self.style
        style.color = self:shade(muted and Pallid.UI.Color.textMuted or Pallid.UI.Color.textPrimary)
        style.maxWidth = math.max(0, self.w - (count > 0 and 46 or 28))
        Pallid.UI.text(el, text, x + 7, y + self.h * 0.5, style)
        style.maxWidth = nil
    end

    if count > 0 and self._clearTexture ~= nil then
        local zoneX, zoneY, zoneW, zoneH = self:clearRect()
        local size = 10
        Pallid.UI.texture(
            el,
            self._clearTexture,
            zoneX + (zoneW - size) * 0.5,
            zoneY + (zoneH - size) * 0.5,
            size,
            size,
            self:shade(Pallid.UI.Color.textMuted),
            ICON_OPTS
        )
    end

    if self._arrowTexture ~= nil then
        local size = 10
        Pallid.UI.texture(el, self._arrowTexture, x + self.w - 6 - size, y + (self.h - size) * 0.5,
            size, size, self:shade(Pallid.UI.Color.textMuted), ICON_OPTS)
    end
end

--- Enables or disables the control.
--- @param enabled boolean New state.
--- @return PallidMultiSelectComboBox self For chaining.
function MultiCombo:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    if not enabled then
        self:close()
    end
    return self
end
