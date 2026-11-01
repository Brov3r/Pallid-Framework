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

--- Searchable dropdown. The closed field shows the selected value; opening it
--- shows a filter field above a virtualised option list, so a list of hundreds
--- of options costs the same as a short one.
---
--- The filter field owns the keyboard while the popover is open: Up/Down move
--- the highlight, Enter accepts, Escape closes. With `allowCustom` an Enter
--- without a highlighted match returns the typed filter text as the value.
---
--- Built on Popover + VirtualList rather than PopupSelect, because PopupSelect
--- owns its own popup geometry and cannot gain a text row without changing the
--- existing dropdown/multiselect behaviour.
--- @class PallidComboBox : PallidWidget
--- @field options (string|table)[] Raw option list.
--- @field value string|nil Current display value.
--- @field selectedIndex integer|nil One-based raw option index.
--- @field allowCustom boolean True accepts typed text that is not an option.
--- @field open boolean True while the popover is visible.
--- @field filterInput PallidInputText Filter field inside the popover.
--- @field list PallidVirtualList Virtualised option list.
--- @field popover PallidPopover Popover that owns the filter and the list.
--- @field onChange fun(combo: PallidComboBox, value: string|nil, index: integer|nil, option: any)|nil Called after the value changes.
--- @field onFilter fun(combo: PallidComboBox, text: string)|nil Called after the filter text changes.
local ComboBox = Widgets.class("ComboBox")

--- Normalises one option into a label/value pair.
--- @param option string|table Source option.
--- @return string label Visible text.
--- @return any value Value returned to the caller.
local function optionLabel(option)
    if type(option) == "table" then
        local label = option.label
        if label == nil then
            label = option.text
        end
        if label == nil then
            label = option.value
        end
        return label == nil and "" or tostring(label)
    end
    return option == nil and "" or tostring(option)
end

--- @param option string|table Source option.
--- @param label string Already normalised label.
--- @return any value Value returned to the caller.
local function optionValue(option, label)
    if type(option) == "table" and option.value ~= nil then
        return option.value
    end
    return label
end

--- Creates a new `ComboBox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[]|nil Option list; tables accept `label`/`text` and `value`.
--- @param opts table|nil Behaviour and appearance.
--- @field opts.placeholder string|nil Field text shown while no value is selected.
--- @field opts.allowCustom boolean|nil True accepts typed text as a value.
--- @field opts.filter string|fun(option: any, label: string, text: string): boolean|nil
---        Initial filter text, or a predicate that decides whether an option matches.
--- @field opts.value string|nil Initial value.
--- @field opts.onChange fun(combo: PallidComboBox, value: string|nil, index: integer|nil, option: any)|nil Value callback.
--- @field opts.onFilter fun(combo: PallidComboBox, text: string)|nil Filter callback.
--- @field opts.maxHeight number|nil Maximum popover list height in pixels, defaults to 200.
--- @field opts.filterPlaceholder string|nil Filter field placeholder.
--- @return PallidComboBox combo New combo box.
function ComboBox.new(x, y, w, h, options, opts)
    opts = opts or {}
    local self = setmetatable({}, ComboBox)
    self:init(x, y, w or 0, h or 0)

    self.placeholder = opts.placeholder
    self.allowCustom = opts.allowCustom == true
    self.onChange = opts.onChange
    self.onFilter = opts.onFilter
    self.maxHeight = math.max(ROW_HEIGHT, math.floor(opts.maxHeight or 200))
    self.rowHeight = ROW_HEIGHT
    self.open = false
    self.value = nil
    self.selectedIndex = nil
    self.filterText = ""
    self._labels = {}
    self._values = {}
    self._raw = {}
    self._filtered = {}
    self._arrowTexture = Pallid.UI.Textures.get(ICON_DIR .. "arrow-down-04.png")
    self._pollUp = false
    self._pollDown = false
    self._pollReturn = false
    self._pollEscape = false

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

    local filterOpt = opts.filter
    if type(filterOpt) == "function" then
        self.filterFn = filterOpt
    elseif type(filterOpt) == "string" then
        self.filterText = filterOpt
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
        itemCount = #self._filtered,
        rowHeight = ROW_HEIGHT,
        selectionMode = "single",
        onSelect = function(_, index)
            self:_chooseFiltered(index)
        end,
        render = function(el, index, rowX, rowY, rowW, rowH, state)
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

    if opts.value ~= nil then
        self:setValue(opts.value, true)
    end
    self:_applyFilter(self.filterText, false)
    return self
end

--- Factory shortcut for `ComboBox.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[]|nil Option list.
--- @param opts table|nil Behaviour and appearance; see `ComboBox.new`.
--- @return PallidComboBox combo New combo box.
function Widgets.comboBox(x, y, w, h, options, opts)
    return ComboBox.new(x, y, w, h, options, opts)
end

--- Replaces the options. The current value is kept when it still exists.
--- @param options (string|table)[]|nil New option list.
--- @param silent boolean|nil True skips `onChange` when the value is cleared.
--- @return PallidComboBox self For chaining.
function ComboBox:setOptions(options, silent)
    local list = type(options) == "table" and options or {}
    self._raw = {}
    self._labels = {}
    self._values = {}
    for i = 1, #list do
        local option = list[i]
        local label = optionLabel(option)
        self._raw[i] = option
        self._labels[i] = label
        self._values[i] = optionValue(option, label)
    end
    self.options = list

    if self.selectedIndex ~= nil and self.selectedIndex > #list then
        self.selectedIndex = nil
        if not silent and self.onChange ~= nil then
            self.onChange(self, self.value, nil, nil)
        end
    end
    if self.list ~= nil then
        self:_applyFilter(self.filterText, false)
    end
    return self
end

--- Rebuilds the filtered index list, keeping the table to avoid a per-keystroke
--- allocation.
--- @param text string|nil New filter text.
--- @param notify boolean True calls `onFilter`.
function ComboBox:_applyFilter(text, notify)
    self.filterText = text or ""
    local filtered = self._filtered
    for i = #filtered, 1, -1 do
        filtered[i] = nil
    end

    local query = string.lower(self.filterText)
    local labels = self._labels
    local raw = self._raw
    local predicate = self.filterFn
    for i = 1, #labels do
        local label = labels[i]
        local matches = query == "" or string.find(string.lower(label), query, 1, true) ~= nil
        if matches and predicate ~= nil then
            matches = predicate(raw[i], label, self.filterText) ~= false
        end
        if matches then
            filtered[#filtered + 1] = i
        end
    end

    if self.list ~= nil then
        self.list:setItemCount(#filtered)
        self.list:scrollTo(0)
        self:_selectCurrentFiltered()
        self:_resizePopover()
    end

    if notify and self.onFilter ~= nil then
        self.onFilter(self, self.filterText)
    end
end

--- Selects the filtered row that matches `selectedIndex`, or the first row.
function ComboBox:_selectCurrentFiltered()
    local filtered = self._filtered
    local target = nil
    if #filtered > 0 then
        target = 1
        if self.selectedIndex ~= nil then
            for i = 1, #filtered do
                if filtered[i] == self.selectedIndex then
                    target = i
                    break
                end
            end
        end
    end
    self.list:setSelected(target, true)
end

--- Resizes the popover and the inner rows to the current option count.
function ComboBox:_resizePopover()
    PopupCombo.resize(self)
end

--- Polls navigation keys while the native filter field owns text entry. The
--- game suppresses `Events.OnKeyPressed` for the whole text-entry period, so
--- raw key state is the only reliable source for arrows/Enter/Escape.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function ComboBox:onUpdate(now, dt)
    PopupCombo.onUpdate(self, now, dt)
end

--- Opens the popover and focuses the filter field.
--- @return PallidComboBox self For chaining.
function ComboBox:show()
    PopupCombo.show(self)
    return self
end

--- Closes the popover.
--- @return PallidComboBox self For chaining.
function ComboBox:close()
    if not self.open then
        return self
    end
    self.open = false
    self.filterInput:blur()
    self.popover:close()
    return self
end

--- @return boolean open True while the popover is visible.
function ComboBox:isOpen()
    return self.open
end

--- Accepts the highlighted filtered row, or the typed custom text.
function ComboBox:_accept()
    local list = self.list
    local index = list.selected
    if index ~= nil and self._filtered[index] ~= nil then
        self:_chooseFiltered(index)
        return
    end
    if self.allowCustom and self.filterText ~= "" then
        self.value = self.filterText
        self.selectedIndex = nil
        self:close()
        if self.onChange ~= nil then
            self.onChange(self, self.value, nil, nil)
        end
    end
end

--- Applies a filtered row click.
--- @param index integer One-based filtered row index.
function ComboBox:_chooseFiltered(index)
    local rawIndex = self._filtered[index]
    if rawIndex == nil then
        return
    end
    self.selectedIndex = rawIndex
    self.value = self._labels[rawIndex]
    local option = self._raw[rawIndex]
    self:close()
    if self.onChange ~= nil then
        self.onChange(self, self.value, rawIndex, option)
    end
end

--- Scrolls the list so a filtered row is visible.
--- @param index integer One-based filtered row index.
function ComboBox:_scrollToRow(index)
    PopupCombo.scrollToRow(self, index)
end

--- Handles keys typed while the filter field is focused.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when the combo consumed the key.
function ComboBox:_onFilterKey(key)
    if Keyboard == nil then
        return false
    end
    if key == Keyboard.KEY_UP or key == Keyboard.KEY_DOWN then
        local count = #self._filtered
        if count == 0 then
            return true
        end
        local current = self.list.selected or 0
        local step = key == Keyboard.KEY_UP and -1 or 1
        local nextIndex = current + step
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
        self:_accept()
        return true
    end
    if key == Keyboard.KEY_ESCAPE then
        self:close()
        return true
    end
    return false
end

--- Sets the value programmatically. Unknown values are accepted only when
--- `allowCustom` is enabled (or when the caller passes `force`).
--- @param value string|nil New value.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidComboBox self For chaining.
function ComboBox:setValue(value, silent)
    self.value = value
    self.selectedIndex = nil
    if value ~= nil then
        local text = tostring(value)
        self.value = text
        for i = 1, #self._values do
            if tostring(self._values[i]) == text or self._labels[i] == text then
                self.selectedIndex = i
                self.value = self._labels[i]
                break
            end
        end
    end
    if not silent and self.onChange ~= nil then
        self.onChange(self, self.value, self.selectedIndex, self.selectedIndex and self._raw[self.selectedIndex] or nil)
    end
    return self
end

--- Returns the current value.
--- @return string|nil value Current display value.
function ComboBox:getValue()
    return self.value
end

--- Returns the selected raw option index.
--- @return integer|nil index One-based option index, or nil for custom/empty values.
function ComboBox:getIndex()
    return self.selectedIndex
end

--- Sets the field text colour.
--- @param color PallidColor New text colour.
--- @return PallidComboBox self For chaining.
function ComboBox:setTextColor(color)
    self.style.color = color
    return self
end

--- Enables or disables the control; disabling closes the popover.
--- @param enabled boolean New state.
--- @return PallidComboBox self For chaining.
function ComboBox:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    if not enabled then
        self:close()
    end
    return self
end

--- Draws one filtered row. No tables are allocated here.
--- @param el ISUIElement Host element.
--- @param index integer One-based filtered row index.
--- @param x number Row left.
--- @param y number Row top.
--- @param w number Row width.
--- @param h number Row height.
--- @param state PallidVirtualRowState Reused row state.
function ComboBox:_drawRow(el, index, x, y, w, h, state)
    local rawIndex = self._filtered[index]
    if rawIndex == nil then
        return
    end
    if state.selected then
        Pallid.UI.rect(el, x, y, w, h, self:shade(Pallid.UI.Color.primarySoft))
    elseif state.hovered then
        Pallid.UI.rect(el, x, y, w, h, self:shade(Pallid.UI.Color.accentSoft))
    end
    local style = self.rowStyle
    style.maxWidth = math.max(0, w - 12)
    style.color = self:shade(Pallid.UI.Color.text)
    Pallid.UI.text(el, self._labels[rawIndex] or "", x + 6, y + h * 0.5, style)
    style.maxWidth = nil
end

--- Handles a press on the closed field or the arrow.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function ComboBox:onDown(px, py, button)
    return PopupCombo.onDown(self, button)
end

--- Closes the popover when the combo leaves the tree.
function ComboBox:onDetach()
    if self.open then
        self.open = false
        self.popover:close()
    end
end

--- Closes the popover when the combo leaves the tree.
function ComboBox:onDetach()
    if self.open then
        self.open = false
        self.popover:close()
    end
end

--- Paints the closed field, its value and the arrow.
--- @param el ISUIElement Host element the tree is rendered into.
function ComboBox:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local radius = 4
    Pallid.UI.roundedRect(el, x, y, self.w, self.h, radius, self:shade(Pallid.UI.Color.surface))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, radius, 1, self:shade(Pallid.UI.Color.border))

    local text = self.value
    local muted = text == nil or text == ""
    if muted then
        text = self.placeholder or ""
    end
    if text ~= "" then
        local style = self.style
        style.color = self:shade(muted and Pallid.UI.Color.textMuted or Pallid.UI.Color.textPrimary)
        style.maxWidth = math.max(0, self.w - 28)
        Pallid.UI.text(el, text, x + 7, y + self.h * 0.5, style)
        style.maxWidth = nil
    end

    if self._arrowTexture ~= nil then
        local size = 10
        Pallid.UI.texture(
            el,
            self._arrowTexture,
            x + self.w - 6 - size,
            y + (self.h - size) * 0.5,
            size,
            size,
            self:shade(Pallid.UI.Color.textMuted),
            ICON_OPTS
        )
    end
end
